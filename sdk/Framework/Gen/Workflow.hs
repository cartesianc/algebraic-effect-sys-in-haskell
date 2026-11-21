-- AST 自己的一段流水线：只看业务树的结构，不读注册与 handler。
-- 完整生成在编号前调用它；`effect-codegen ast` 单独调用它，供 LSP 在注册或 handler 有错时仍能读树。
module Framework.Gen.Workflow (hangingMarks, prepareWorkflow, checkWorkflowShape, SourceSite(..), SourceRange(..)) where

import Control.Monad (forM_, unless, when)
import Data.List (nub)
import Framework.Language.AST (WorkflowF(..), normalizeWorkflow)
import Framework.Prototype.Types (NodeId, PrototypeError(..))
import Framework.Recursion (Fix(..))

-- 源码中的一个 AST 位置（原样结构中的路径）：经过的具名绑定（外层在前）、写出这一层结构的源码范围，
-- 以及结构能否从源码读出。不能读出时（例如由普通 Haskell 计算得到），没有下层位置。
data SourceSite = SourceSite
  { sitePath :: [Int]
  , siteNames :: [String]
  , siteRange :: Maybe SourceRange
  , siteReadable :: Bool
  } deriving (Eq, Show)

-- GHC 的源码范围：文件、起止行列（从 1 开始，结束列不含）。
data SourceRange = SourceRange FilePath Int Int Int Int
  deriving (Eq, Show)

-- Hanging 的每一行：求值得到的 hook 与目标数，配上前端从源码定位的目标名及其全部源码位置。
-- 结果是源码位置上的挂载；迁移到规范形式由 prepareWorkflow 完成。
hangingMarks :: [([String], Int)] -> [[(String, [NodeId])]] -> Either String [(NodeId, [String])]
hangingMarks rows targets = do
  unless (length rows == length targets) (Left "Hanging source differs from its declaration")
  concat <$> sequence
    [ do
        unless (arity == length refs && arity > 0) (Left "middleware needs a nonempty list of named workflow branches")
        unless (length (nub (map fst refs)) == length refs) (Left "middleware lists a workflow branch twice")
        forM_ refs $ \(name, paths) -> when (null paths) (Left ("Hanging target is unreachable from AST.ast: " ++ name))
        pure [(path, hooks) | (_, paths) <- refs, path <- paths]
    | ((hooks, arity), refs) <- zip rows targets ]

-- 规范化业务树，把源码位置上的 Hanging 挂载迁移到规范形式中覆盖同一子树的位置，再做结构检查。
-- 被拼入外层的分支自身不执行调用，挂在它各子项上的覆盖范围与原来相同。
prepareWorkflow :: Fix WorkflowF -> [(NodeId, [String])]
                -> Either (PrototypeError String) (Fix WorkflowF, [(NodeId, [String])])
prepareWorkflow tree marks = do
  let (normalized, relocate) = normalizeWorkflow tree
  checkWorkflowShape normalized
  pure (normalized, [(moved, hooks) | (path, hooks) <- marks, moved <- relocate path])

-- 规范形式上的结构规则，路径是规范形式中的 NodeId。
-- 末端类别、持续订阅与 alternative 的判定 Context 要读注册，在编号时检查。
checkWorkflowShape :: Fix WorkflowF -> Either (PrototypeError String) ()
checkWorkflowShape = check [] False
  where
    -- inside：是否位于 lifelong 内。lifelong 不嵌套；其中每条成功路径都要领取交付，所以不能有空分支。
    check path inside (Fix layer) = case layer of
      Node _ -> pure ()
      Chained children -> nonEmpty path inside children >> descend path inside children
      Parallel children -> nonEmpty path inside children >> descend path inside children
      Lifelong children -> do
        when inside $ Left (InvalidLifelong path "lifelong cannot be nested")
        nonEmpty path True children
        descend path True children
      -- 候选是末端：一个候选就是一条 original chain，候选之前的步骤写在注册的 Input 链上。
      -- 只有一个候选时没有可选择的分支：要在 Excu 的输出上执行它，用 requests 声明驱动。
      Alternative children -> do
        unless (length children >= 2) $ Left (InvalidAlternative path ("alternative needs at least two candidates"
          ++ "; to run a single branch on a parsed asset, declare requests for that asset instead"))
        unless (all terminal children) $ Left (InvalidAlternative path
          "alternative candidates must be nodes; put the steps before a candidate on its Input chain")
    descend path inside children = sequence_ [check (path ++ [index]) inside child | (index, child) <- zip [0 ..] children]
    nonEmpty path inside children = when (inside && null children) $
      Left (InvalidLifelong path "an empty branch inside lifelong never takes a delivery")
    terminal (Fix (Node _)) = True
    terminal _ = False
