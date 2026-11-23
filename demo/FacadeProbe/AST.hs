module FacadeProbe.AST (ast) where

import Framework.SDK (AST, alternative, chain, lifelong, node, parallel)
import qualified FacadeProbe.Workflow.Abc
import Framework.SDK (AST, chain, parallel, alternative, lifelong, node)

ast :: AST
ast = chain
  [ parallel [node "WriteReport", node "WriteReply"]
  , chain [node "ShowReport", node "ShowReply"]
  , alternative [node "OnBlank", node "OnFilled"]
  , parallel [lifelong [node "ShowA"], lifelong [node "ShowB"]], FacadeProbe.Workflow.Abc.abc
  ]
