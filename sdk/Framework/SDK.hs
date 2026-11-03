-- 手写业务的公共入口：声明、资产访问能力与 workflow 组合。
-- 业务 main 使用本程序 Generated.Program 的 interpreter；生成包装和执行装配
-- 使用 Framework.Generated，不在这里暴露存储、scope 控制对象或裸运行入口。
module Framework.SDK
  ( module Framework.Effect
  , AST, EffectNode, node, chained, parallel, alternative, lifelong
  ) where

import Framework.Effect
import Framework.Workflow.AST (AST, EffectNode, node, chained, parallel, alternative, lifelong)
