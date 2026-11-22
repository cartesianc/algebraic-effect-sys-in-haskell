{-# LANGUAGE ScopedTypeVariables #-}

-- 业务模块的顶层白名单：这是 gen 自己的架构规则，GHC 构建不检查。
-- 需要类型的角色（具名 AST、hangingTree）读取本次类型检查的结果；Main 只按语法检查，
-- 因为它导入生成的 Program，生成区的类型检查留给构建。
module Framework.Gen.Check.TopLevel (checkTopLevel, checkMainSource) where

import Data.Data (Data, cast, gmapQ)
import Data.List (isPrefixOf)
import GHC
import GHC.Core.Type (splitTyConApp_maybe)
import GHC.Core.TyCon (tyConName)
import GHC.Hs.Utils (CollectFlag(..), collectHsBindBinders)
import GHC.Types.Name (nameModule_maybe, nameOccName)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.Name.Reader (rdrNameOcc)
import GHC.Types.Var (Var, varName, varType)
import GHC.Unit.Module (moduleNameString)
import GHC.Utils.Outputable (ppr, showSDocUnsafe)

data ModuleRole = EffectsModule | WorkflowModule | HangingModule | MainModule | OtherModule deriving Eq

-- 业务模块的顶层只允许类型声明、instance，以及固定的注册、workflow 与入口值：
-- Effects 的 effects，AST 与 Workflow 的具名 AST，Hanging 的 hangingTree，以及 Main 的 main。
-- 顶层普通函数一律拒绝：值操作写在 handler 方法体内，经注册进入 effect 链，才能被静态分析。
-- 方法体内的局部函数与 lambda 不受限制。
checkTopLevel :: String -> TypecheckedModule -> [String]
checkTopLevel namespace checked = case tm_renamed_source checked of
  Nothing -> ["Top-level checking requires renamed source"]
  Just (group, _, _, _, _) ->
    [ at (getLocA binding) ++ "top-level definition " ++ occNameString (nameOccName binder) ++ " is not allowed in "
        ++ sourceModule ++ "; " ++ advice
    | binding <- topBindings (hs_valds group)
    , binder <- collectHsBindBinders CollNoDictBinders (unLoc binding), not (allowed binder) ]
    ++ [ at (getLocA declaration) ++ "class declaration " ++ occNameString (nameOccName (unLoc (tcdLName (unLoc declaration))))
          ++ " is not allowed in " ++ sourceModule ++ "; handler classes are generated from registrations"
       | classes <- hs_tyclds group, declaration@(L _ ClassDecl {}) <- group_tyclds classes ]
    ++ [ at (getLocA declaration) ++ "foreign declaration is not allowed in " ++ sourceModule
       | declaration <- hs_fords group ]
    ++ [ at (getLocA declaration) ++ "rewrite rule is not allowed in " ++ sourceModule
       | declaration <- hs_ruleds group ]
  where
    sourceModule = moduleNameString (moduleName (ms_mod (pm_mod_summary (tm_parsed_module checked))))
    role
      | sourceModule == namespace ++ ".Effects" = EffectsModule
      | sourceModule == namespace ++ ".Hanging" = HangingModule
      | sourceModule == namespace ++ ".Main" = MainModule
      | sourceModule == namespace ++ ".AST" || (namespace ++ ".Workflow.") `isPrefixOf` sourceModule = WorkflowModule
      | otherwise = OtherModule
    allowed binder = case role of
      HangingModule -> occNameString (nameOccName binder) == "hangingTree"
        && any (declarationType "HangingTree" . snd) (filter ((== binder) . fst) typed)
      EffectsModule -> occNameString (nameOccName binder) == "effects"
      MainModule -> occNameString (nameOccName binder) == "main"
      WorkflowModule -> any (declarationType "AST" . snd) (filter ((== binder) . fst) typed)
      OtherModule -> False
    advice = adviceFor role
    declarationType expected selected = case splitTyConApp_maybe selected of
      Just (constructor, []) -> let name = tyConName constructor
        in occNameString (nameOccName name) == expected
          && fmap (moduleNameString . moduleName) (nameModule_maybe name) == Just "Framework.Language.AST"
      _ -> False
    typed = typedVariables (tm_typechecked_source checked)

-- Main 的同一条规则按解析结果检查：只定义 main，没有 class、foreign 与 rule。
checkMainSource :: String -> HsModule GhcPs -> [String]
checkMainSource namespace parsed =
  [ at (getLocA declaration) ++ "top-level definition " ++ occNameString (rdrNameOcc binder) ++ " is not allowed in "
      ++ sourceModule ++ "; " ++ adviceFor MainModule
  | declaration@(L _ (ValD _ binding)) <- hsmodDecls parsed
  , binder <- collectHsBindBinders CollNoDictBinders binding, occNameString (rdrNameOcc binder) /= "main" ]
  ++ [ at (getLocA declaration) ++ "class declaration " ++ occNameString (rdrNameOcc (unLoc name))
        ++ " is not allowed in " ++ sourceModule ++ "; handler classes are generated from registrations"
     | declaration@(L _ (TyClD _ ClassDecl {tcdLName = name})) <- hsmodDecls parsed ]
  ++ [ at (getLocA declaration) ++ "foreign declaration is not allowed in " ++ sourceModule
     | declaration@(L _ ForD {}) <- hsmodDecls parsed ]
  ++ [ at (getLocA declaration) ++ "rewrite rule is not allowed in " ++ sourceModule
     | declaration@(L _ RuleD {}) <- hsmodDecls parsed ]
  where
    sourceModule = namespace ++ ".Main"

adviceFor :: ModuleRole -> String
adviceFor role = case role of
  HangingModule -> "Hanging.hs defines only hangingTree :: HangingTree"
  EffectsModule -> "Effects.hs defines only effects; local helpers may stay in its where clause"
  WorkflowModule -> "workflow modules define only named AST values"
  MainModule -> "Main.hs defines only main"
  OtherModule -> "write value operations inside handler methods (local functions there are fine)"

at :: SrcSpan -> String
at location = showSDocUnsafe (ppr location) ++ ": "

topBindings :: HsValBinds GhcRn -> [LHsBind GhcRn]
topBindings bindings = case bindings of
  ValBinds _ values _ -> values
  XValBindsLR (NValBinds groups _) -> concatMap snd groups

-- 类型检查后的绑定名与其类型；不遍历类型本身。
typedVariables :: Data value => value -> [(Name, Type)]
typedVariables value
  | Just (identifier :: Var) <- cast value = [(varName identifier, varType identifier)]
  | Just (_ :: Type) <- cast value = []
  | otherwise = concat (gmapQ typedVariables value)
