-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}
-- handler 是不带参数的类方法；SDK 按注册装配上游、会话与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module LinesDemo.Generated.Handlers (handlerSourceFingerprint, runAnnounce, getOpenedInput, readOpenedInput, openInputSession, closeInputSession, nextLineFeed, getTextLine, streamTextLine, runPrintLine, runReport, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.Generated as FrameworkRuntime
import qualified LinesDemo.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import LinesDemo.Types
import Framework.SDK (Ends(..), History, Raises(..), Raw(..), Reads(..), historySize, latest)
import LinesDemo.Generated.Effects
import LinesDemo.Types
import Control.Monad.IO.Class (liftIO)
import System.FilePath ((</>))
import System.IO (IOMode(ReadMode), hClose, hGetLine, hIsEOF, openFile)

instance AnnounceLayer m => AnnounceHandler m where
  announce = do
    liftIO (putStrLn "Reading the input line by line.")
    pure []

-- 输入文件在第一次读行时由 InputSession 取得，之后的各步骤共用同一个 Handle。
instance AcquireInputLayer m => AcquireInputHandler m where
  acquireInput = do
    let path = "demo" </> "LinesDemo" </> "input.txt"
    file <- liftIO (openFile path ReadMode)
    pure (InputFile path file)

instance OpenInputLayer m => OpenInputHandler m where
  openInput = do
    InputFile path _ <- require @InputFile
    liftIO (putStrLn ("[open] " ++ path))
    pure []

instance CloseInputLayer m => CloseInputHandler m where
  closeInput = do
    InputFile path file <- require @InputFile
    liftIO (hClose file >> putStrLn ("[close] " ++ path))
    pure []

-- 一次读一行。文件读完时 end：这一步不交出输入，parser 不执行，生产会话正常结束；
-- 已经发布的行仍会交给 PrintLine 处理完。
instance NextLineLayer m => NextLineHandler m where
  nextLine = do
    InputFile _ file <- require @InputFile
    finished <- liftIO (hIsEOF file)
    if finished then end else liftIO (hGetLine file)

instance ParseLineLayer m => ParseLineHandler m where
  parseLine = do
    text <- concat <$> raw
    pure (Line text)

instance PrintLineLayer m => PrintLineHandler m where
  printLine = do
    received <- require @(History Line)
    case latest received of
      Just (Line text) -> liftIO (putStrLn ("line " ++ show (historySize received) ++ ": " ++ text))
      Nothing -> pure ()
    pure []

instance ReportLayer m => ReportHandler m where
  report = do
    liftIO (putStrLn "The input ended and every line was handled.")
    pure []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "6dd3c5d73e7e42d673e1cfedfcea19dd"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AnnounceError (At effect) where
  raise (FrameworkGenerated.AnnounceError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AnnounceFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AcquireInputError (At effect) where
  raise (FrameworkGenerated.AcquireInputError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AcquireInputFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenInputError (At effect) where
  raise (FrameworkGenerated.OpenInputError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenInputFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CloseInputError (At effect) where
  raise (FrameworkGenerated.CloseInputError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CloseInputFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.NextLineError (At effect) where
  raise (FrameworkGenerated.NextLineError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.NextLineFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ParseLineError (At effect) where
  raise (FrameworkGenerated.ParseLineError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ParseLineFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.PrintLineError (At effect) where
  raise (FrameworkGenerated.PrintLineError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.PrintLineFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReportError (At effect) where
  raise (FrameworkGenerated.ReportError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReportFailure description)

instance FrameworkRuntime.Reads (InputFile) (At "InputSession") where
  require = At ((\(FrameworkGenerated.OpenedInput value) -> value) <$> readOpenedInput)

instance FrameworkRuntime.Reads (InputFile) (At "LineFeed") where
  require = At ((\(FrameworkGenerated.OpenedInput value) -> value) <$> readOpenedInput)

instance FrameworkRuntime.Reads (FrameworkRuntime.History (Line)) (At "PrintLine") where
  require = At (fmap (\(FrameworkGenerated.TextLine value) -> value) <$> streamTextLine)

instance FrameworkRuntime.Raw (At "LineParser") where
  raw = At ((: []) <$> nextLineFeed)

instance FrameworkRuntime.Ends (At "LineFeed") where
  end = At FrameworkRuntime.endStream

runAnnounce :: FrameworkGenerated.App [String]
runAnnounce = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runAnnounce" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "Announce") $
  runAt @"Announce" FrameworkGenerated.announce

getOpenedInput :: FrameworkGenerated.App FrameworkGenerated.OpenedInput
getOpenedInput = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "InputResource"
    (\value bindings -> bindings { FrameworkGenerated.boundInputResource = Just value })) $
  (FrameworkGenerated.OpenedInput <$> runAt @"InputResource" FrameworkGenerated.acquireInput)

readOpenedInput :: FrameworkGenerated.App FrameworkGenerated.OpenedInput
readOpenedInput = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "InputResource" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundInputResource

openInputSession :: FrameworkGenerated.App [String]
openInputSession = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openInputSession" . FrameworkRuntime.openScope "InputSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "InputSession") $
  getOpenedInput >> runAt @"InputSession" FrameworkGenerated.openInput

closeInputSession :: FrameworkGenerated.App [String]
closeInputSession = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeInputSession" . FrameworkRuntime.closeScope "InputSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "InputSession") $
  runAt @"InputSession" FrameworkGenerated.closeInput

nextLineFeed :: FrameworkGenerated.App String
nextLineFeed = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.streamHandle . FrameworkRuntime.withScopeDependencies ["InputSession"] . FrameworkRuntime.enterHandler "LineFeed") $
  openInputSession >> runAt @"LineFeed" FrameworkGenerated.nextLine

getTextLine :: FrameworkGenerated.App FrameworkGenerated.TextLine
getTextLine = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["InputSession"] . FrameworkRuntime.callContext "LineParser"
    (\value bindings -> bindings { FrameworkGenerated.boundLineParser = Just value })) $
  (FrameworkGenerated.TextLine <$> runAt @"LineParser" FrameworkGenerated.parseLine)

streamTextLine :: FrameworkGenerated.App (FrameworkRuntime.History FrameworkGenerated.TextLine)
streamTextLine = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readHistory "LineParser" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundLineParser

runPrintLine :: FrameworkGenerated.App [String]
runPrintLine = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runPrintLine" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrintLine") $
  runAt @"PrintLine" FrameworkGenerated.printLine

runReport :: FrameworkGenerated.App [String]
runReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReport" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "Report") $
  runAt @"Report" FrameworkGenerated.report

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "InputSession" [] (Just "InputResource")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("InputSession", () <$ closeInputSession)
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [
  ]
