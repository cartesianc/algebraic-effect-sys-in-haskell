module FacadeProbe.AST (ast) where

import Framework.SDK (AST, alternative, chained, lifelong, node, parallel)

ast :: AST
ast = chained
  [ parallel [node "WriteReport", node "WriteReply"]
  , parallel [node "ReadReport", node "ReadReply"]
  , chained [node "ShowReport", node "ShowReply"]
  , alternative [node "OnBlank", node "OnFilled"]
  , lifelong [node "ShowA", node "ShowB"]
  ]
