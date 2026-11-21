module FacadeProbe.AST (ast) where

import Framework.SDK (AST, alternative, chain, lifelong, node, parallel)

ast :: AST
ast = chain
  [ parallel [node "WriteReport", node "WriteReply"]
  , chain [node "ShowReport", node "ShowReply"]
  , alternative [node "OnBlank", node "OnFilled"]
  , lifelong [node "ShowA", node "ShowB"]
  ]
