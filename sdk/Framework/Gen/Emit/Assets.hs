-- 类检后的资产目录只在这里渲染；不解释业务来源或生命周期。
module Framework.Gen.Emit.Assets (renderAssets) where
import Data.List (intercalate)
import Framework.Prototype.Catalog

renderAssets :: String -> [Asset] -> String
renderAssets namespace assets = unlines
  [ "-- 自动生成的源码资产目录；不包含业务值或 Context 来源，不参与运行时生命周期。"
  , "module " ++ namespace ++ ".Generated.Assets (generatedAssets) where"
  , ""
  , "import Framework.Prototype.Catalog (Asset(..), AssetSymbol(..))"
  , ""
  , "generatedAssets :: [Asset]"
  , "generatedAssets ="
  , if null assets then "  []" else "  [ " ++ intercalate "\n  , " (map renderAsset assets) ++ "\n  ]"
  ]
  where
    renderAsset asset = "Asset\n      { assetType = " ++ show (assetType asset)
      ++ "\n      , assetConstructors =" ++ symbols (assetConstructors asset)
      ++ "\n      , assetFields =" ++ symbols (assetFields asset)
      ++ "\n      }"
    symbols [] = " []"
    symbols values = "\n          [ " ++ intercalate "\n          , " (map show values) ++ "\n          ]"
