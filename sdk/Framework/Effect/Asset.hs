-- 源码资产目录，不保存业务值、Context 来源或 scope 运行状态。
module Framework.Effect.Asset (Asset(..), AssetSymbol(..)) where

data AssetSymbol = AssetSymbol
  { assetModule :: String
  , assetName :: String
  , assetFile :: FilePath
  , assetLine :: Int
  , assetColumn :: Int
  } deriving (Eq, Ord, Show, Read)

data Asset = Asset
  { assetType :: AssetSymbol
  , assetConstructors :: [AssetSymbol]
  , assetFields :: [AssetSymbol]
  } deriving (Eq, Ord, Show, Read)
