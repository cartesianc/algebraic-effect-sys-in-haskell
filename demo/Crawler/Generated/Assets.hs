-- 自动生成的源码资产目录；不包含业务值或 Context 来源，不参与运行时生命周期。
module Crawler.Generated.Assets (generatedAssets) where

import Framework.Effect.Asset (Asset(..), AssetSymbol(..))

generatedAssets :: [Asset]
generatedAssets =
  [ Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "CrawlSessionInfo", assetFile = "demo/Crawler/Types.hs", assetLine = 17, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "CrawlSessionInfo", assetFile = "demo/Crawler/Types.hs", assetLine = 17, assetColumn = 25}
          ]
      , assetFields =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "sessionName", assetFile = "demo/Crawler/Types.hs", assetLine = 18, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "sessionUserAgent", assetFile = "demo/Crawler/Types.hs", assetLine = 19, assetColumn = 5}
          ]
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "FetchedPage", assetFile = "demo/Crawler/Types.hs", assetLine = 22, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "FetchedHTML", assetFile = "demo/Crawler/Types.hs", assetLine = 22, assetColumn = 20}
          ]
      , assetFields =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "fetchedURL", assetFile = "demo/Crawler/Types.hs", assetLine = 23, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "fetchedBody", assetFile = "demo/Crawler/Types.hs", assetLine = 24, assetColumn = 5}
          ]
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "LinkedFetchedPage", assetFile = "demo/Crawler/Types.hs", assetLine = 35, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "LinkedFetchedPage", assetFile = "demo/Crawler/Types.hs", assetLine = 35, assetColumn = 29}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "LinkedPageSummary", assetFile = "demo/Crawler/Types.hs", assetLine = 37, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "LinkedPageSummary", assetFile = "demo/Crawler/Types.hs", assetLine = 37, assetColumn = 29}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "LinkedURL", assetFile = "demo/Crawler/Types.hs", assetLine = 15, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "LinkedURL", assetFile = "demo/Crawler/Types.hs", assetLine = 15, assetColumn = 21}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "PageSummary", assetFile = "demo/Crawler/Types.hs", assetLine = 27, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "PageSummary", assetFile = "demo/Crawler/Types.hs", assetLine = 27, assetColumn = 20}
          ]
      , assetFields =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "summaryURL", assetFile = "demo/Crawler/Types.hs", assetLine = 28, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "summaryTitle", assetFile = "demo/Crawler/Types.hs", assetLine = 29, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "summaryContent", assetFile = "demo/Crawler/Types.hs", assetLine = 30, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "summaryLinks", assetFile = "demo/Crawler/Types.hs", assetLine = 31, assetColumn = 5}
          ]
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "PageURL", assetFile = "demo/Crawler/Types.hs", assetLine = 8, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "PageURL", assetFile = "demo/Crawler/Types.hs", assetLine = 8, assetColumn = 16}
          ]
      , assetFields =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "pageAddress", assetFile = "demo/Crawler/Types.hs", assetLine = 9, assetColumn = 5}
          ]
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "StartFetchedPage", assetFile = "demo/Crawler/Types.hs", assetLine = 34, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "StartFetchedPage", assetFile = "demo/Crawler/Types.hs", assetLine = 34, assetColumn = 28}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "StartPageSummary", assetFile = "demo/Crawler/Types.hs", assetLine = 36, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "StartPageSummary", assetFile = "demo/Crawler/Types.hs", assetLine = 36, assetColumn = 28}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "StartURL", assetFile = "demo/Crawler/Types.hs", assetLine = 14, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "StartURL", assetFile = "demo/Crawler/Types.hs", assetLine = 14, assetColumn = 20}
          ]
      , assetFields = []
      }
  ]
