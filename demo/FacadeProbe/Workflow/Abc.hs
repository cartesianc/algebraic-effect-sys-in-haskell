module FacadeProbe.Workflow.Abc (abc) where

import Framework.SDK (AST, chain, parallel, alternative, lifelong, node)

abc :: AST
abc = parallel [node "ReplyScope"]
