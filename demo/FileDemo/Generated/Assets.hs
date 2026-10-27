-- 自动生成的源码资产目录；不包含业务值或 Context 来源，不参与运行时生命周期。
module FileDemo.Generated.Assets (generatedAssets) where

import Framework.Effect.Asset (Asset(..), AssetSymbol(..))

generatedAssets :: [Asset]
generatedAssets =
  [ Asset
      { assetType = AssetSymbol {assetModule = "FileDemo.Types", assetName = "FileName", assetFile = "demo/FileDemo/Types.hs", assetLine = 5, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "FileDemo.Types", assetName = "FileName", assetFile = "demo/FileDemo/Types.hs", assetLine = 5, assetColumn = 20}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "FileDemo.Types", assetName = "FileText", assetFile = "demo/FileDemo/Types.hs", assetLine = 12, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "FileDemo.Types", assetName = "FileText", assetFile = "demo/FileDemo/Types.hs", assetLine = 12, assetColumn = 20}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "FileDemo.Types", assetName = "OpenedFile", assetFile = "demo/FileDemo/Types.hs", assetLine = 9, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "FileDemo.Types", assetName = "OpenedFile", assetFile = "demo/FileDemo/Types.hs", assetLine = 9, assetColumn = 19}
          ]
      , assetFields = []
      }
  ]
