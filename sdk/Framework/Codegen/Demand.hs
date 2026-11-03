{-# LANGUAGE ScopedTypeVariables #-}

-- 检查资产的接收形态与声明依据。只读取 GHC 已解析的名字和显式语法，
-- 不移动取值、不执行 handler，也不证明所有路径都会使用字段。
module Framework.Codegen.Demand (checkDemands) where

import Control.Monad (forM)
import Data.Data (Data, cast, gmapQ)
import Data.List (intercalate, nub)
import Framework.Effect.Demand (AccessResult(..), accessResult, readsAccess)
import Framework.Effect.Registration (Access(..), ResolvedDemand(..))
import Framework.Prototype
import GHC
import GHC.Core.ConLike (ConLike(..))
import GHC.Core.DataCon (dataConName, dataConTyCon)
import GHC.Core.TyCon (tyConDataCons)
import GHC.Hs
import GHC.Types.Name (nameModule_maybe, nameOccName)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Unit.Module (moduleNameString)
import GHC.Utils.Outputable (ppr, showSDocUnsafe)

-- 调用位置用于把实际取值与它的接收语句关联；Name 保留模块与命名空间身份。
data AccessSite = AccessSite
  { accessSite :: SrcSpan
  , accessMethod :: String
  , accessContract :: Name
  } deriving (Eq)

-- Assets 已完成原生源码的名称解析和类型检查，检查器不另行加载业务。
-- 每个 instance 只要求资产有显式读取或已装配的控制流依据，
-- 不要求所有协议方法、所有访问模式或每条成功路径都重复读取它。
checkDemands :: String -> Prototype String -> [(String, String)] -> TypecheckedModule -> Ghc [String]
checkDemands namespace prototype methods checked = case tm_renamed_source checked of
  Nothing -> pure ["Demand checking requires renamed source"]
  Just (group, _, _, _, _) -> do
    let selected = registeredInstances group
        bindings = concat [values | (_, _, values) <- selected]
        sites = nub (concatMap accesses bindings)
        constructors = nub (concatMap patternConstructors bindings)
    resolvedConstructors <- forM constructors $ \name -> do
      found <- lookupName name
      pure (name, case found of
        Just (AConLike (RealDataCon constructor)) -> length (tyConDataCons (dataConTyCon constructor)) == 1
        _ -> False)
    resolvedContracts <- forM (nub (map accessContract sites)) $ \name -> do
      found <- lookupName name
      pure (name, case found of
        Just (ATyCon selectedType) -> case tyConDataCons selectedType of
          [constructor] -> Just (dataConName constructor)
          _ -> Nothing
        _ -> Nothing)
    pure (concatMap (checkInstance resolvedConstructors resolvedContracts) selected)
  where
    contractsModule = namespace ++ ".Generated.Effects"
    named name = occNameString (nameOccName name)
    inContracts name = fmap (moduleNameString . moduleName) (nameModule_maybe name) == Just contractsModule
    effects = protoEffects prototype
    control = controlReads prototype
    registeredInstances group =
      [ (owner, locA location, [unLoc binding | binding <- cid_binds declaration, registered owner (unLoc binding)])
      | classes <- hs_tyclds group
      , L location (ClsInstD _ declaration) <- group_instds classes
      , Just owner <- [className (sig_body (unLoc (cid_poly_ty declaration)))]
      , inContracts owner
      , any ((== named owner) . fst) methods ]
    registered owner FunBind {fun_id = identifier} = (named owner, named (unLoc identifier)) `elem` methods
    registered _ _ = False
    effectOf owner = [effect | effect <- effects, effectName effect ++ "Effect" == named owner]
    checkInstance constructors contracts (owner, location, bindings) =
      let sites = nub (concatMap accesses bindings)
          receipts = nub (concatMap (receptions constructors contracts) bindings)
          observed = map (named . accessContract) sites
          missing = nub [demandContract demand | effect <- effectOf owner, demand <- effectDemands effect
            , demandContract demand `notElem` observed
            , (effectName effect, demandContract demand) `notElem` control]
      in [at location ++ named owner ++ " declares asset(s) without a registered-method read or workflow delivery: "
            ++ intercalate ", " missing ++ "; receive them explicitly or remove the unused demands"
          | not (null missing)]
        ++ concatMap snd receipts
        ++ [at (accessSite site) ++ "receive " ++ describe site
              ++ " with an explicit asset pattern, or bind it before a case; do not discard/pass the action through a helper"
           | site <- sites, site `notElem` map fst receipts]
    at location = showSDocUnsafe (ppr location) ++ ": "
    describe site = accessMethod site ++ " @" ++ named (accessContract site)
    accessExpression located = case unLoc (stripExpression located) of
      HsAppType _ function argument -> case unLoc (stripExpression function) of
        HsVar _ identifier
          | inContracts (unLoc identifier), named (unLoc identifier) `elem` ["request", "require"]
          , Just contract <- namedType (hswc_body argument), inContracts contract ->
              Just (AccessSite (getLocA located) (named (unLoc identifier)) contract)
        _ -> Nothing
      _ -> Nothing
    accesses :: Data value => value -> [AccessSite]
    accesses value
      | Just (expression :: LHsExpr GhcRn) <- cast value
      , Just selected <- accessExpression expression = [selected]
      | otherwise = concat (gmapQ accesses value)
    -- 仅在 GHC 已确认的标准 bind 上识别 continuation，避免同名业务函数被当成接收语法。
    bindOperator expression = case unLoc (stripExpression expression) of
      HsVar _ identifier
        | fmap (moduleNameString . moduleName) (nameModule_maybe (unLoc identifier))
            `elem` map Just ["GHC.Base", "GHC.Internal.Base"] -> Just (named (unLoc identifier))
      _ -> Nothing
    bindParts expression = case expression of
      OpApp _ left operator right -> pair (bindOperator operator) left right
      HsApp _ first right -> case unLoc (stripExpression first) of
        HsApp _ operator left -> pair (bindOperator operator) left right
        _ -> Nothing
      _ -> Nothing
      where
        pair (Just ">>=") action continuation = Just (action, continuation)
        pair (Just "=<<") continuation action = Just (action, continuation)
        pair _ _ _ = Nothing
    receptions :: Data value => [(Name, Bool)] -> [(Name, Maybe Name)] -> value -> [(AccessSite, [String])]
    receptions constructors contracts value = here ++ concat (gmapQ (receptions constructors contracts) value)
      where
        here = case cast value of
          Just (expression :: HsExpr GhcRn) -> case expression of
            HsDo _ (DoExpr Nothing) statements ->
              [ receipt False site pattern' rest
              | (L _ (BindStmt _ pattern' action), rest) <- withRemainders (unLoc statements)
              , Just site <- [accessExpression action] ]
            _ -> case bindParts expression of
              Just (action, continuation) | Just site <- accessExpression action ->
                case unLoc (stripExpression continuation) of
                  HsLam _ variant matches ->
                    [(site, concat [case unLoc (m_pats match) of
                        [pattern'] -> snd (receipt (case variant of LamSingle -> False; _ -> True) site pattern' (m_grhss match))
                        _ -> [at (accessSite site) ++ "asset reception needs a single-argument lambda/case"]
                      | L _ match <- unLoc (mg_alts matches)])]
                  _ -> []
              _ -> []
          Nothing -> []
        receipt alternatives site pattern' following =
          (site, [at (accessSite site) ++ "receive " ++ describe site ++ " as " ++ expected site
            | not (accepts alternatives site pattern' following)])
        expected site
          | isHistory site = "a named History view; its constructors remain abstract"
          | otherwise = named (accessContract site)
              ++ " ...; use a bound value and case for refutable constructor alternatives"
        accepts :: Data following => Bool -> AccessSite -> LPat GhcRn -> following -> Bool
        accepts alternatives site pattern' following
          | isHistory site = variablePattern (unLoc pattern') /= Nothing -- History stays an explicit whole-value binding.
          | directPattern site (unLoc pattern') = alternatives || irrefutable constructors (unLoc pattern')
          | Just variable <- variablePattern (unLoc pattern') = any
              (\patterns -> not (null patterns) && all (directPattern site . unLoc) patterns)
              (casesOf variable following)
          | otherwise = False
        directPattern site pattern' = case pattern' of
          ConPat {pat_con = identifier} -> lookup (accessContract site) contracts == Just (Just (unLoc identifier))
          ParPat _ inner -> directPattern site (unLoc inner)
          BangPat _ inner -> directPattern site (unLoc inner)
          AsPat _ _ inner -> directPattern site (unLoc inner)
          SigPat _ inner _ -> directPattern site (unLoc inner)
          _ -> False
    isHistory site = accessResult continuous mode == AssetHistory
      where
        mode = if accessMethod site == "request" then RequestAccess else RequireAccess
        continuous = any (\effect -> effectProduces effect == Just (named (accessContract site))
          && effectContinuous effect) effects

-- 数据来源由已有 Prototype 判定。输入链上的声明参与选择/交付，
-- 所以即使某个方法只调用上游、没有再读一次，它仍可具有消费依据。
controlReads :: Prototype method -> [(String, String)]
controlReads prototype = nub (walk (protoWorkflow prototype))
  where
    effects = protoEffects prototype
    inherited selected = selected : concat [effectInputChain effect | effect <- effects, effectName effect == selected]
    demandsOf selected = [(effectName effect, demand) | effect <- effects, effectName effect `elem` inherited selected
      , demand <- effectDemands effect]
    walk tree = here tree ++ concatMap walk (workflowChildren tree)
    here (LifelongAt _ description _) =
      [(consumer, demandContract demand) | (path, contract) <- lifelongSubscriptions description
        , Just (NodeAt _ selected) <- [lookupWorkflow (protoWorkflow prototype) path]
        , (consumer, demand) <- demandsOf selected
        , demandAccess demand == StreamAccess, demandContract demand == contract]
    here (AlternativeAt _ description _) =
      [(consumer, demandContract demand) | (path, constructor) <- alternativeCases description
        , Just subtree <- [lookupWorkflow (protoWorkflow prototype) path]
        , selected <- workflowTerminals subtree
        , (consumer, demand) <- demandsOf selected, readsAccess (demandAccess demand)
        , producer <- effects, effectProduces producer == Just (alternativeContract description)
        , (branch, selectedConstructor) <- effectBranches producer
        , branch == demandContract demand, selectedConstructor == constructor]
    here _ = []

withRemainders :: [value] -> [(value, [value])]
withRemainders [] = []
withRemainders (value : rest) = (value, rest) : withRemainders rest

stripExpression :: LHsExpr GhcRn -> LHsExpr GhcRn
stripExpression expression = case unLoc expression of
  HsPar _ inner -> stripExpression inner
  ExprWithTySig _ inner _ -> stripExpression inner
  HsPragE _ _ inner -> stripExpression inner
  _ -> expression

namedType :: LHsType GhcRn -> Maybe Name
namedType located = case unLoc located of
  HsTyVar _ _ name -> Just (unLoc name)
  HsParTy _ inner -> namedType inner
  _ -> Nothing

className :: LHsType GhcRn -> Maybe Name
className located = case unLoc located of
  HsQualTy {hst_body = body} -> className body
  HsForAllTy {hst_body = body} -> className body
  HsAppTy _ function _ -> className function
  HsParTy _ inner -> className inner
  _ -> namedType located

variablePattern :: Pat GhcRn -> Maybe Name
variablePattern pattern' = case pattern' of
  VarPat _ name -> Just (unLoc name)
  ParPat _ inner -> variablePattern (unLoc inner)
  BangPat _ inner -> variablePattern (unLoc inner)
  SigPat _ inner _ -> variablePattern (unLoc inner)
  _ -> Nothing

-- 只关联同一已解析变量的显式 case；不追踪别名、闭包调用或泛型值流。
casesOf :: Data value => Name -> value -> [[LPat GhcRn]]
casesOf name value = here ++ concat (gmapQ (casesOf name) value)
  where
    here = case cast value of
      Just (HsCase _ scrutinee alternatives :: HsExpr GhcRn)
        | HsVar _ selected <- unLoc (stripExpression scrutinee), unLoc selected == name ->
            [concat [unLoc (m_pats match) | L _ match <- unLoc (mg_alts alternatives)]]
      _ -> []

patternConstructors :: Data value => value -> [Name]
patternConstructors value = here ++ concat (gmapQ patternConstructors value)
  where
    here = case cast value of
      Just (ConPat {pat_con = name} :: Pat GhcRn) -> [unLoc name]
      _ -> []

-- 单构造器的逐层解构可直接接收；值筛选和可能失败的匹配应显式进入 case/raise。
-- 构造器数量来自 GHC，而不是凭名字推断，也不引入 MonadFail。
irrefutable :: [(Name, Bool)] -> Pat GhcRn -> Bool
irrefutable constructors pattern' = case pattern' of
  WildPat {} -> True
  VarPat {} -> True
  ParPat _ inner -> irrefutable constructors (unLoc inner)
  BangPat _ inner -> irrefutable constructors (unLoc inner)
  AsPat _ _ inner -> irrefutable constructors (unLoc inner)
  SigPat _ inner _ -> irrefutable constructors (unLoc inner)
  TuplePat _ fields _ -> all (irrefutable constructors . unLoc) fields
  ConPat {pat_con = name, pat_args = arguments} -> lookup (unLoc name) constructors == Just True
    && all (irrefutable constructors) (nestedPatterns arguments)
  _ -> False
  where
    nestedPatterns :: Data value => value -> [Pat GhcRn]
    nestedPatterns value
      | Just pattern' <- cast value = [pattern']
      | otherwise = concat (gmapQ nestedPatterns value)
