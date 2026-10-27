-- 自动生成的源码资产目录；不包含业务值或 Context 来源，不参与运行时生命周期。
module Crawler.Generated.Assets (generatedAssets) where

import Framework.Effect.Asset (Asset(..), AssetSymbol(..))

generatedAssets :: [Asset]
generatedAssets =
  [ Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "CrawlSessionInfo", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 52, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "CrawlSessionInfo", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 52, assetColumn = 28}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "LinkedFetchedPage", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 44, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "LinkedFetchedPage", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 44, assetColumn = 29}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "LinkedPageSummary", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 48, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "LinkedPageSummary", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 48, assetColumn = 29}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "LinkedURL", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 32, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "LinkedURL", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 32, assetColumn = 21}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "StartFetchedPage", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 36, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "StartFetchedPage", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 36, assetColumn = 28}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "StartPageSummary", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 40, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "StartPageSummary", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 40, assetColumn = 28}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "StartURL", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 28, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Generated.Effects", assetName = "StartURL", assetFile = "demoCrawler/Generated/Effects.hs", assetLine = 28, assetColumn = 20}
          ]
      , assetFields = []
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "FetchedPage", assetFile = "demo/Crawler/Types.hs", assetLine = 18, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "FetchedHTML", assetFile = "demo/Crawler/Types.hs", assetLine = 18, assetColumn = 20}
          ]
      , assetFields =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "fetchedURL", assetFile = "demo/Crawler/Types.hs", assetLine = 19, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "fetchedBody", assetFile = "demo/Crawler/Types.hs", assetLine = 20, assetColumn = 5}
          ]
      }
  , Asset
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "PageSummary", assetFile = "demo/Crawler/Types.hs", assetLine = 23, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "PageSummary", assetFile = "demo/Crawler/Types.hs", assetLine = 23, assetColumn = 20}
          ]
      , assetFields =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "summaryURL", assetFile = "demo/Crawler/Types.hs", assetLine = 24, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "summaryTitle", assetFile = "demo/Crawler/Types.hs", assetLine = 25, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "summaryContent", assetFile = "demo/Crawler/Types.hs", assetLine = 26, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "summaryLinks", assetFile = "demo/Crawler/Types.hs", assetLine = 27, assetColumn = 5}
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
      { assetType = AssetSymbol {assetModule = "Crawler.Types", assetName = "SessionInfo", assetFile = "demo/Crawler/Types.hs", assetLine = 13, assetColumn = 1}
      , assetConstructors =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "SessionInfo", assetFile = "demo/Crawler/Types.hs", assetLine = 13, assetColumn = 20}
          ]
      , assetFields =
          [ AssetSymbol {assetModule = "Crawler.Types", assetName = "sessionName", assetFile = "demo/Crawler/Types.hs", assetLine = 14, assetColumn = 5}
          , AssetSymbol {assetModule = "Crawler.Types", assetName = "sessionUserAgent", assetFile = "demo/Crawler/Types.hs", assetLine = 15, assetColumn = 5}
          ]
      }
  ]
