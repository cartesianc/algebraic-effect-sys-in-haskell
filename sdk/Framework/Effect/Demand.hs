-- 资产接收契约的纯规则。Registration 保存声明，Prototype 保存解析结果；
-- 本模块不保存第二份资产表、不运行 handler、不依赖 GHC 的源码解析器。
-- 同一个 refined asset 只有一个静态 Context 来源，访问模式不产生新的资产身份。
-- 实际 publication、Origin、scope ownership 和交付游标由 runtime 决定。
module Framework.Effect.Demand
  ( validateAssetSources, resolveDemands, contextNames
  , readsAccess, accessOperation, AccessResult(..), accessResult
  ) where

import Control.Monad (unless)
import Data.List (nub)
import Framework.Effect.Registration

-- 先校验整个注册集合，包括当前没有消费者的资产；不按访问模式挑选生产方。
validateAssetSources :: [EffectSpec] -> Either String ()
validateAssetSources specifications =
  unless (length names == length (nub names)) (Left "Duplicate Context contract")
  where
    names = [contractOf declared | specification <- specifications
             , Just declared <- [contextAsset (typing specification)]]

-- streams 当前通过 require 读取控制流已经固定的交付视图，不授予主动 request。
readsAccess :: Access -> Bool
readsAccess RequestAccess = False
readsAccess RequireAccess = True
readsAccess StreamAccess = True

accessOperation :: Access -> String
accessOperation RequestAccess = "request"
accessOperation RequireAccess = "require"
accessOperation StreamAccess = "require"

-- 返回形态仍属于同一资产。当前持续 require 是历史；单值/历史拆分属于后续阶段。
-- 投影契约不是持续基础契约，调用方按已解析的基础/投影身份传入 False。
data AccessResult = AssetValue | AssetHistory deriving (Eq, Show, Read)

accessResult :: Bool -> Access -> AccessResult
accessResult continuous selected
  | readsAccess selected && continuous = AssetHistory
  | otherwise = AssetValue

findEffect :: [EffectSpec] -> String -> Either String EffectSpec
findEffect specifications selected = case filter ((== selected) . name) specifications of
  [specification] -> Right specification
  [] -> Left ("Unknown effect: " ++ selected)
  _ -> Left ("Duplicate effect: " ++ selected)

produced :: EffectSpec -> Maybe String
produced specification = contractOf <$> contextAsset (typing specification)

-- 资产名在注册集合中唯一，因此每个契约恰好对应一个生产方。
-- 取值模式须对应生产方已声明的角色：request 需要 request 角色，require 需要 require 角色。
-- branches：和类型资产的分支契约 → 基础契约；分支契约由基础契约的生产方提供（投影）。
resolveDemands :: [(String, String)] -> [EffectSpec] -> EffectSpec -> Either String [ResolvedDemand]
resolveDemands branches specifications consumer = do
  validateAssetSources specifications
  let keys = [(access demand, contract demand) | demand <- demands consumer]
  unless (length keys == length (nub keys)) $
    Left ("Duplicate demand in " ++ name consumer ++ "; each asset/access pair may be declared once")
  mapM resolveOne (demands consumer)
  where
    resolveOne demand = do
      let producedContract = maybe (contract demand) id (lookup (contract demand) branches)
      provider <- case [specification | specification <- specifications
            , name specification /= name consumer, produced specification == Just producedContract] of
        [specification] -> pure specification
        [] -> Left ("No Context produces contract " ++ contract demand ++ " for " ++ name consumer
          ++ "; a contract is the asset name declared by its producer Context")
        _ -> Left ("Several Context effects produce contract " ++ producedContract)
      case (access demand, typing provider) of
        (RequestAccess, _) | belowStream specifications provider -> Left ("Contract " ++ contract demand
          ++ " is parsed from Stream input by its session, so " ++ name consumer ++ " cannot request it")
        (RequestAccess, Context { request = Nothing }) -> Left ("Contract " ++ contract demand
          ++ " has no request role, so " ++ name consumer ++ " cannot request it")
        (RequireAccess, Context { require = Nothing }) -> Left ("Contract " ++ contract demand
          ++ " has no require role, so " ++ name consumer ++ " cannot require it")
        (StreamAccess, Context {}) | not (continuousContext specifications provider) -> Left ("Contract " ++ contract demand
          ++ " is not a continuous asset (hang its Context below a Stream, or declare stream = Just ()), so "
          ++ name consumer ++ " cannot subscribe to it")
        (StreamAccess, Context { require = Nothing }) -> Left ("Contract " ++ contract demand
          ++ " has no require role, so " ++ name consumer ++ " cannot read its deliveries")
        (StreamAccess, _) | producedContract /= contract demand -> Left ("Branch contract " ++ contract demand
          ++ " cannot be subscribed; subscribe to " ++ producedContract ++ " in " ++ name consumer)
        _ -> pure ()
      pure (ResolvedDemand (access demand) (contract demand) (name provider))

-- 收集声明前提所需的 Context，按依赖顺序去重；不根据业务值合并调用。
contextNames :: [(String, String)] -> [EffectSpec] -> [String] -> Either String [String]
contextNames branches specifications selected = nub . concat <$> mapM (visit []) selected
  where
    visit _ "Root" = Right []
    visit seen selectedName
      | selectedName `elem` seen = Left ("Cyclic input/demand: " ++ selectedName)
      | otherwise = do
          specification <- findEffect specifications selectedName
          resolved <- resolveDemands branches specifications specification
          let providers = nub (map demandProvider resolved)
          upstream <- concat <$> mapM (visit (selectedName : seen)) (nub (input specification : providers))
          pure (upstream ++ providers)
