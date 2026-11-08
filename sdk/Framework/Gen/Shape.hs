{-# LANGUAGE ScopedTypeVariables #-}

-- handler 方法体的纯结构副本；只保留按表示类型的读取与 raw，不求值业务数据或 IO。
-- 读取 @T 与 raw 的来源因绑定而异，由 gen 在每个绑定上替换为 effect 方法调用。
module Framework.Gen.Shape (shapeHandlers, analyzeModule) where

import Control.Monad (unless)
import Data.Data (Data, cast, gmapQ)
import Data.List (nub)
import Framework.Gen.Source (HandlerSource(..))
import Framework.Prototype.Graph (MethodShape(..))
import GHC (GhcPs)
import GHC.Hs
import GHC.Hs.Utils (CollectFlag(..), collectLocalBinders, collectPatBinders)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.Name.Reader (RdrName(..), rdrNameOcc)
import GHC.Types.SrcLoc (GenLocated(..), unLoc)
import GHC.Unit.Module (moduleNameString)
import GHC.Utils.Outputable (ppr, showSDocUnsafe)

data Environment = Environment
  { contractsModule :: String
  , handlerMethods :: [(String, String)]
  , imports :: [ImportDecl GhcPs]
  , boundNames :: [String]
  , hasImplicitPrelude :: Bool
  -- 当前所在的 handler 类，用于诊断。
  , ownerClass :: Maybe String
  }

-- SDK 中 handler 能力的导出模块。
capabilityModules :: [String]
capabilityModules = ["Framework.SDK", "Framework.Language.Handler"]

-- 形状阶段：分析 Handlers.hs 中各 handler 的方法体。RebindableSyntax 下 do 不按标准语义展开，不分析。
shapeHandlers :: String -> [(String, String)] -> HandlerSource -> Either String [(String, MethodShape String)]
shapeHandlers namespace handlers source = do
  analyzed <- analyzeModule namespace handlers (handlerImplicitPrelude source) (handlerModule source)
  if handlerRebindable source && any ((/= Empty) . snd) analyzed
    then Left "Effect structure analysis does not support RebindableSyntax; use standard Haskell in handler bodies"
    else pure analyzed

-- 每个 handler 方法体得到一份结构：require @T 记为 @T，raw 记为 %raw。
-- handler 不能调用其他 handler：组合只经注册的 Input、demands 与 AST。
analyzeModule
  :: String -> [(String, String)] -> Bool -> HsModule GhcPs
  -> Either String [(String, MethodShape String)]
analyzeModule namespace handlers implicitPrelude parsed = do
  unless (length (nub (map snd handlers)) == length handlers) $
    Left "Structure analysis needs distinct handler names"
  concat <$> mapM instanceShapes (hsmodDecls parsed)
  where
    environment = Environment (namespace ++ ".Generated.Effects") handlers
      (map unLoc (hsmodImports parsed)) [] implicitPrelude Nothing
    instanceShapes (L _ (InstD _ (ClsInstD _ declaration))) =
      case classIdentifier (sig_body (unLoc (cid_poly_ty declaration))) of
        Just identifier
          | let owner = identifierName identifier
          , owner `elem` map fst handlers ->
              if imported environment [contractsModule environment] Nothing identifier
                then concat <$> mapM (methodShape owner) (cid_binds declaration)
                else Left ("Cannot resolve handler class " ++ owner
                  ++ "; import " ++ contractsModule environment ++ " directly for structure analysis")
        _ -> pure []
    instanceShapes _ = pure []
    methodShape owner (L _ FunBind {fun_id = identifier, fun_matches = matches})
      | (owner, method) `elem` handlers = do
          result <- prefixError method (shapeMatches environment {ownerClass = Just owner} matches)
          pure [(method, result)]
      where method = identifierName (unLoc identifier)
    methodShape _ _ = pure []

prefixError :: String -> Either String value -> Either String value
prefixError location = either (Left . (("Cannot analyze " ++ location ++ ": ") ++)) Right

classIdentifier :: LHsType GhcPs -> Maybe RdrName
classIdentifier located = case unLoc located of
  HsQualTy {hst_body = body} -> classIdentifier body
  HsForAllTy {hst_body = body} -> classIdentifier body
  HsParTy _ body -> classIdentifier body
  HsAppTy _ function _ -> classIdentifier function
  HsTyVar _ _ identifier -> Just (unLoc identifier)
  _ -> Nothing

identifierName :: RdrName -> String
identifierName = occNameString . rdrNameOcc

shadow :: [String] -> Environment -> Environment
shadow names environment = environment {boundNames = names ++ boundNames environment}

patternNames :: LPat GhcPs -> [String]
patternNames = map identifierName . collectPatBinders CollNoDictBinders

localEnvironment :: Environment -> HsLocalBinds GhcPs -> Environment
localEnvironment environment =
  flip shadow environment . map identifierName . collectLocalBinders CollNoDictBinders

-- 只识别真正导入的名称；qualified alias 与 hiding 都参与。
-- 局部 pattern/let/where 名称优先，不把同名业务变量误当作 SDK 能力或 handler。
-- require 记为带 @ 前缀的取值标记，须配合类型实参；handler 方法记为带 ! 前缀的标记，在调用处拒绝。
methodReference :: Environment -> RdrName -> Maybe String
methodReference environment identifier
  | identifierName identifier == "require"
  , imported environment capabilityModules (Just "Reads") identifier = Just "@require"
  | identifierName identifier == "raw"
  , imported environment capabilityModules (Just "Raw") identifier = Just "%raw"
  | otherwise = case
      [method | (owner, method) <- handlerMethods environment
        , method == identifierName identifier
        , imported environment [contractsModule environment] (Just owner) identifier] of
      [method] -> Just ('!' : method)
      _ -> Nothing

-- require @T 记为按表示类型的读取；类型原文由 gen 规范化后与绑定的路由比较。
demandCall :: LHsWcType GhcPs -> Either String (MethodShape String)
demandCall argument = pure (Call ('@' : showSDocUnsafe (ppr (hswc_body argument))))

-- handler 之间不直接调用：被调用的 handler 不经 effect 入口，Input、驱动和错误位置都会丢失。
directCall :: Environment -> String -> Either String (MethodShape String)
directCall environment reference = case reference of
  "@require" -> Left "require needs an explicit representation type, e.g. require @PageURL"
  '!' : method -> Left ("handler " ++ maybe "" (++ " ") (ownerClass environment) ++ "calls handler " ++ method
    ++ " directly; compose handlers through effect registrations (Input, demands) and the AST")
  _ -> pure (Call reference)

imported :: Environment -> [String] -> Maybe String -> RdrName -> Bool
imported environment modules owner identifier = case identifier of
  Unqual _ -> identifierName identifier `notElem` boundNames environment
    && (any (matches Nothing) (imports environment) || implicitPrelude)
  Qual qualifier _ -> any (matches (Just (moduleNameString qualifier))) (imports environment)
  _ -> False
  where
    name = identifierName identifier
    implicitPrelude = hasImplicitPrelude environment && "Prelude" `elem` modules
      && not (any ((== "Prelude") . moduleNameString . unLoc . ideclName) (imports environment))
    matches qualifier declaration =
      moduleNameString (unLoc (ideclName declaration)) `elem` modules
      && case qualifier of
        Nothing -> ideclQualified declaration == NotQualified && allows declaration
        Just selected -> selected == maybe (moduleNameString (unLoc (ideclName declaration)))
          (moduleNameString . unLoc) (ideclAs declaration) && allows declaration
    allows declaration = case ideclImportList declaration of
      Nothing -> True
      Just (interpretation, entries) ->
        let listed = any (includes . unLoc) (unLoc entries)
        in case interpretation of Exactly -> listed; EverythingBut -> not listed
    includes (IEVar _ wrapped _) = wrappedName wrapped == name
    includes (IEThingAbs _ wrapped _) = wrappedName wrapped == name
    includes (IEThingAll _ wrapped _) = wrappedName wrapped == name || Just (wrappedName wrapped) == owner
    includes (IEThingWith _ wrapped _ members _) = wrappedName wrapped == name
      || any ((== name) . wrappedName) members
    includes _ = False

wrappedName :: LIEWrappedName GhcPs -> String
wrappedName located = case unLoc located of
  IEName _ identifier -> identifierName (unLoc identifier)
  IEDefault _ identifier -> identifierName (unLoc identifier)
  IEPattern _ identifier -> identifierName (unLoc identifier)
  IEType _ identifier -> identifierName (unLoc identifier)

-- 引用扫描也遵守词法作用域。未支持的纯业务语法没有 effect 引用时直接擦除。
references :: Data value => Environment -> value -> [String]
references environment value
  | Just expression <- cast value = expressionReferences environment expression
  | Just matches <- cast value = matchesReferences environment matches
  | Just rhss <- cast value = rhsReferences environment rhss
  | otherwise = concat (gmapQ (references environment) value)

expressionReferences :: Environment -> HsExpr GhcPs -> [String]
expressionReferences environment expression = case expression of
  HsVar _ identifier -> maybe [] pure (methodReference environment (unLoc identifier))
  HsLet _ bindings body ->
    let nested = localEnvironment environment bindings
    in references nested bindings ++ references nested body
  HsDo _ (MDoExpr _) statements ->
    statementReferences (afterStatements environment (unLoc statements)) (unLoc statements)
  HsDo _ _ statements -> statementReferences environment (unLoc statements)
  _ -> concat (gmapQ (references environment) expression)

matchesReferences :: Environment -> Match GhcPs (LHsExpr GhcPs) -> [String]
matchesReferences environment Match {m_pats = patterns, m_grhss = rhss} =
  references environment (unLoc patterns)
    ++ rhsReferences (shadow (concatMap patternNames (unLoc patterns)) environment) rhss

rhsReferences :: Environment -> GRHSs GhcPs (LHsExpr GhcPs) -> [String]
rhsReferences environment GRHSs {grhssGRHSs = rhss, grhssLocalBinds = bindings} =
  let nested = localEnvironment environment bindings
  in references nested bindings ++ concatMap (guardedReferences nested . unLoc) rhss

guardedReferences :: Environment -> GRHS GhcPs (LHsExpr GhcPs) -> [String]
guardedReferences environment (GRHS _ guards body) =
  statementReferences environment guards ++ references (afterStatements environment guards) body

afterStatements :: Environment -> [ExprLStmt GhcPs] -> Environment
afterStatements = foldl advance
  where
    advance environment (L _ (BindStmt _ pattern' _)) = shadow (patternNames pattern') environment
    advance environment (L _ (LetStmt _ bindings)) = localEnvironment environment bindings
    advance environment (L _ RecStmt {recS_stmts = statements}) = afterStatements environment (unLoc statements)
    advance environment _ = environment

statementReferences :: Environment -> [ExprLStmt GhcPs] -> [String]
statementReferences _ [] = []
statementReferences environment (statement : rest) =
  current ++ statementReferences next rest
  where
    next = afterStatements environment [statement]
    current = case unLoc statement of
      LetStmt _ bindings -> references next bindings
      RecStmt {recS_stmts = statements} -> statementReferences next (unLoc statements)
      _ -> references environment (unLoc statement)

rejectReferences :: Data value => Environment -> String -> value -> Either String ()
rejectReferences environment description value =
  unless (null (references environment value)) $
    Left (description ++ "; bind the asset with require before using it")

sequenceShape :: [MethodShape String] -> MethodShape String
sequenceShape shapes = case concatMap flatten shapes of
  [] -> Empty
  [shape] -> shape
  remaining -> Sequence remaining
  where flatten Empty = []; flatten (Sequence children) = children; flatten shape = [shape]

choiceShape :: [MethodShape String] -> MethodShape String
choiceShape [] = Empty
choiceShape [shape] = shape
choiceShape shapes | all (== Empty) shapes = Empty
choiceShape shapes = Choice shapes

shapeMatches :: Environment -> MatchGroup GhcPs (LHsExpr GhcPs) -> Either String (MethodShape String)
shapeMatches environment MG {mg_alts = alternatives} =
  choiceShape <$> mapM (shapeMatch environment . unLoc) (unLoc alternatives)

shapeMatch :: Environment -> Match GhcPs (LHsExpr GhcPs) -> Either String (MethodShape String)
shapeMatch environment Match {m_pats = patterns, m_grhss = rhss} = do
  rejectReferences environment "effect reference in a pattern" (unLoc patterns)
  shapeRhss (shadow (concatMap patternNames (unLoc patterns)) environment) rhss

shapeRhss :: Environment -> GRHSs GhcPs (LHsExpr GhcPs) -> Either String (MethodShape String)
shapeRhss environment GRHSs {grhssGRHSs = rhss, grhssLocalBinds = bindings} = do
  let nested = localEnvironment environment bindings
  rejectReferences nested "effect reference in a where binding" bindings
  choiceShape <$> mapM (shapeGuarded nested . unLoc) rhss

shapeGuarded :: Environment -> GRHS GhcPs (LHsExpr GhcPs) -> Either String (MethodShape String)
shapeGuarded environment (GRHS _ guards body) = do
  unless (null (statementReferences environment guards)) $
    Left "effect reference in a guard; bind the Context before the branch"
  shapeExpression (afterStatements environment guards) body

shapeStatements :: Environment -> [ExprLStmt GhcPs] -> Either String (MethodShape String)
shapeStatements _ [] = pure Empty
shapeStatements environment (statement : rest) = do
  let next = afterStatements environment [statement]
  current <- case unLoc statement of
    BindStmt _ pattern' body -> do
      rejectReferences environment "effect reference in a binding pattern" pattern'
      shapeExpression environment body
    BodyStmt _ body _ _ -> shapeExpression environment body
    LastStmt _ body _ _ -> shapeExpression environment body
    LetStmt _ bindings -> do
      rejectReferences next "effect reference in a let binding" bindings
      pure Empty
    other -> rejectReferences environment "unsupported effect statement" other >> pure Empty
  following <- shapeStatements next rest
  pure (sequenceShape [current, following])

shapeExpression :: Environment -> LHsExpr GhcPs -> Either String (MethodShape String)
shapeExpression environment located
  | null (references environment located) = pure Empty
  | otherwise = case unLoc located of
      HsVar _ identifier -> maybe unsupported (directCall environment)
        (methodReference environment (unLoc identifier))
      HsPar _ body -> shapeExpression environment body
      HsAppType _ (L _ (HsVar _ identifier)) argument
        | Just "@require" <- methodReference environment (unLoc identifier) -> demandCall argument
      HsAppType _ body _ -> shapeExpression environment body
      ExprWithTySig _ body _ -> shapeExpression environment body
      HsPragE _ _ body -> shapeExpression environment body
      HsDo _ (DoExpr Nothing) statements -> shapeStatements environment (unLoc statements)
      HsIf _ condition yes no -> do
        rejectReferences environment "effect reference in an if condition" condition
        choiceShape <$> mapM (shapeExpression environment) [yes, no]
      HsCase _ value alternatives -> do
        rejectReferences environment "effect reference in a case scrutinee" value
        shapeMatches environment alternatives
      HsMultiIf _ alternatives -> choiceShape <$> mapM (shapeGuarded environment . unLoc) alternatives
      HsLet _ bindings body -> do
        let nested = localEnvironment environment bindings
        rejectReferences nested "effect reference in a let binding" bindings
        shapeExpression nested body
      HsApp {} -> uncurry (shapeApplication environment) (application located)
      OpApp _ left operator right -> do
        -- GHC parser 尚未根据导入 fixity 重关联；混合 operator 必须显式括号化。
        let operators = operatorSpine located
        unless (length (nub operators) <= 1 && not (operators == replicate (length operators) "$" && length operators > 1)) $
          Left "parenthesize mixed effect operators before structure analysis"
        if known environment "$" operator
          then let (function, arguments) = application left
            in shapeApplication environment function (arguments ++ [right])
          else shapeApplication environment operator [left, right]
      _ -> unsupported
  where
    unsupported = Left "unsupported use of require/raw; bind it in a do statement, or use if/case or a supported combinator"

application :: LHsExpr GhcPs -> (LHsExpr GhcPs, [LHsExpr GhcPs])
application expression = case unLoc expression of
  HsApp _ function argument -> let (head', arguments) = application function in (head', arguments ++ [argument])
  HsPar _ body -> application body
  HsAppType _ body _ -> application body
  _ -> (expression, [])

operatorSpine :: LHsExpr GhcPs -> [String]
operatorSpine expression = case unLoc expression of
  OpApp _ left operator right -> operatorSpine left ++ maybe [] pure (variableName operator) ++ operatorSpine right
  _ -> []

variableName :: LHsExpr GhcPs -> Maybe String
variableName expression = case unLoc expression of
  HsVar _ identifier -> Just (identifierName (unLoc identifier))
  HsPar _ body -> variableName body
  _ -> Nothing

known :: Environment -> String -> LHsExpr GhcPs -> Bool
known environment expected expression = case unLoc expression of
  HsVar _ identifier -> identifierName (unLoc identifier) == expected
    && imported environment modules owner (unLoc identifier)
  HsPar _ body -> known environment expected body
  HsAppType _ body _ -> known environment expected body
  _ -> False
  where
    (modules, owner)
      | expected == "catchError" = (["Control.Monad.Except", "Control.Monad.Error.Class"], Just "MonadError")
      | expected `elem` ["when", "unless", "replicateM_"] = (["Control.Monad"], Nothing)
      | expected == "void" = (["Control.Monad", "Data.Functor"], Nothing)
      | expected == "forM_" = (["Control.Monad", "Data.Foldable"], Nothing)
      | expected == "mapM_" = (["Control.Monad", "Data.Foldable", "Prelude"], Nothing)
      | expected `elem` [">>", ">>=", "=<<"] = (["Prelude", "Control.Monad"], Just "Monad")
      | expected `elem` ["<*>", "<*", "*>"] = (["Prelude", "Control.Applicative"], Just "Applicative")
      | expected `elem` ["<$>", "<$"] = (["Prelude", "Data.Functor"], Just "Functor")
      | otherwise = (["Prelude", "Data.Either", "Data.Maybe"], Nothing)

shapeApplication :: Environment -> LHsExpr GhcPs -> [LHsExpr GhcPs] -> Either String (MethodShape String)
shapeApplication environment function arguments = case arguments of
  [left, right] | is ">>" || is "*>" || is "<*" || is "<*>" -> serial [left, right]
  [action, continuation] | is ">>=" -> combine action continuation
  [continuation, action] | is "=<<" -> combine action continuation
  [action, recovery] | is "catchError" -> do
    body <- shapeExpression environment action
    handler <- shapeContinuation environment recovery
    pure (Recover body handler)
  [condition, action] | is "when" || is "unless" -> do
    rejectReferences environment "effect reference in a condition" condition
    choiceShape . (Empty :) . pure <$> shapeExpression environment action
  [value, action] | is "<$>" || is "<$" -> do
    rejectReferences environment "effect reference in a pure mapping function/value" value
    shapeExpression environment action
  [action] | is "void" -> shapeExpression environment action
  [left, right, value] | is "either" -> do
    rejectReferences environment "effect reference in an either scrutinee" value
    choiceShape <$> mapM (shapeContinuation environment) [left, right]
  [fallback, branch, value] | is "maybe" -> do
    rejectReferences environment "effect reference in a maybe scrutinee" value
    left <- shapeExpression environment fallback
    right <- shapeContinuation environment branch
    pure (choiceShape [left, right])
  _ -> Left ("unsupported higher-order effect composition"
    ++ maybe "" (": " ++) (variableName function)
    ++ "; use explicit registered calls and do/if/case (effect loops need a repetition contract)")
  where
    is name = known environment name function
    serial expressions = sequenceShape <$> mapM (shapeExpression environment) expressions
    combine action continuation = do
      first <- shapeExpression environment action
      next <- shapeContinuation environment continuation
      pure (sequenceShape [first, next])

shapeContinuation :: Environment -> LHsExpr GhcPs -> Either String (MethodShape String)
shapeContinuation environment expression
  | null (references environment expression) = pure Empty
  | otherwise = case unLoc expression of
      HsLam _ _ matches -> shapeMatches environment matches
      HsPar _ body -> shapeContinuation environment body
      _ -> Left "effect continuation must be an explicit lambda/case; do not pass it through a higher-order function"
