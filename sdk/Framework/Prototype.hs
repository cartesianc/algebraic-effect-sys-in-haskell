-- 编译产物（Prototype）的门面：gen 构建它，执行装配与结构展示读取它，三者共用同一份静态事实。
-- Types 是数据模型，Graph 是方法图与 ScopeTree 的数据，Query 是只读查询，Validate 是自洽与快照核对；
-- 构建算法属于编译器（Framework.Gen.Lower、Framework.Gen.Build），不经本模块导出。
module Framework.Prototype
  ( module Framework.Prototype.Types
  , module Framework.Prototype.Graph
  , module Framework.Prototype.Query
  , module Framework.Prototype.Validate
  ) where

import Framework.Prototype.Graph
import Framework.Prototype.Query
import Framework.Prototype.Types
import Framework.Prototype.Validate (validatePrototype, validateWorkflow, matchWorkflowLayer)
