-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeOperators #-}
-- handler 是不带参数的类方法；SDK 按注册装配上游、会话与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module LinesDemo.Generated.Handlers (handlerSourceFingerprint, runAnnounce, getOpenedInput, readOpenedInput, openInputSession, closeInputSession, nextLineFeed, hookTraceLine, getTextLine, streamTextLine, runPrintLine, runTextCounter, getRunningTotal, streamRunningTotal, runShowTotal, runReport, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified LinesDemo.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Emits(rawemit), Hooks(hook), Operation(..), StreamEnds(..), Raises(..), Raw(..), Reads(..), rawoutput)
import LinesDemo.Generated.Effects
import LinesDemo.Types
import Control.Monad.IO.Class (liftIO)
import Data.IORef (atomicModifyIORef', newIORef)
import System.FilePath ((</>))
import System.IO (IOMode(ReadMode), hClose, hGetLine, hIsEOF, openFile)

instance AnnounceLayer m => AnnounceHandler m where
  announce = do
    liftIO (putStrLn "Reading the input line by line.")
    rawoutput []

-- 输入文件在第一次读行时由 InputSession 取得，之后的各步骤共用同一个 Handle。
instance AcquireInputLayer m => AcquireInputHandler m where
  acquireInput = do
    let path = "demo" </> "LinesDemo" </> "input.txt"
    file <- liftIO (openFile path ReadMode)
    counter <- liftIO (newIORef (Total 0 0))
    pure (InputFile path file counter)

instance OpenInputLayer m => OpenInputHandler m where
  openInput = do
    InputFile path _ _ <- require @InputFile
    liftIO (putStrLn ("[open] " ++ path))
    rawoutput []

instance CloseInputLayer m => CloseInputHandler m where
  closeInput = do
    InputFile path file _ <- require @InputFile
    liftIO (hClose file >> putStrLn ("[close] " ++ path))
    rawoutput []

-- 在一次来源调用内持续读取。每个 rawemit 都完成这行的解析与发布，再读取下一行。
instance NextLineLayer m => NextLineHandler m where
  nextLine = do
    InputFile _ file _ <- require @InputFile
    let readLines = do
          finished <- liftIO (hIsEOF file)
          if finished then streamEnd else do
            line <- liftIO (hGetLine file)
            rawemit line
            readLines
    readLines

instance TraceLineLayer m => TraceLineHandler m where
  traceLine = do
    op <- hook
    case op of
      Enter name -> liftIO (putStrLn ("[enter] " ++ name))
      RawInput name fields -> liftIO (putStrLn ("[input] " ++ name ++ ": " ++ show fields))
      RawOutput name fields -> liftIO (putStrLn ("[output] " ++ name ++ ": " ++ show fields))
      RawEmit name text -> liftIO (putStrLn ("[emit] " ++ name ++ ": " ++ text))
      Raise name reason -> liftIO (putStrLn ("[raise] " ++ name ++ ": " ++ reason))
    rawoutput []

instance ParseLineLayer m => ParseLineHandler m where
  parseLine = do
    text <- concat <$> rawinput
    pure (Line text)

instance PrintLineLayer m => PrintLineHandler m where
  printLine = do
    Line text <- require @Line
    liftIO (putStrLn ("line: " ++ text))
    rawoutput []

-- 由 TextLine 驱动：每来一行执行一次。计数是业务状态，SDK 只交付本次 Line。
instance CountTextLayer m => CountTextHandler m where
  countText = do
    Line text <- require @Line
    InputFile _ _ counter <- require @InputFile
    Total count size <- liftIO $ atomicModifyIORef' counter $ \(Total previousCount previousSize) ->
      let count = previousCount + 1
          size = previousSize + length text
          updated = Total count size
      in count `seq` size `seq` (updated, updated)
    rawoutput [show count, show size]

instance ParseTotalLayer m => ParseTotalHandler m where
  parseTotal = do
    fields <- rawinput
    case fields of
      [count, size] -> pure (Total (read count) (read size))
      _ -> raise (ParseTotalError "the counter gives a line count and a character count")

instance ShowTotalLayer m => ShowTotalHandler m where
  showTotal = do
    Total count size <- require @Total
    liftIO (putStrLn ("  so far: " ++ show count ++ " lines, " ++ show size ++ " characters"))
    rawoutput []

instance ReportLayer m => ReportHandler m where
  report = do
    Total count size <- require @Total
    liftIO (putStrLn ("The selected total is: " ++ show count ++ " lines, " ++ show size ++ " characters."))
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "65972ef14476f7caeea09207461d7d9d"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (hooks :: [FrameworkTypes.Symbol]) (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

-- superhandler 的静态选择：hooks 是覆盖本次挂载的 Middleware（注册顺序），kind 是捕获类别。
-- 默认方法即空选择：不捕获，super 直接执行 action。
class Captures (hooks :: [FrameworkTypes.Symbol]) (kind :: SDK.EffectKind) where
  captureAt :: SDK.Operation -> Effects.App ()
  captureAt _ = pure ()
  superWrap :: String -> Effects.App value -> Effects.App value
  closeWrap :: String -> Effects.App [String] -> Effects.App [String]
  superWrap _ = id
  closeWrap _ = id

-- 入口对 hooks 多态：每个被拦截的类别都有该列表的选择。
type Captured hooks = (Captures hooks 'SDK.StreamKind, Captures hooks 'SDK.ScopedKind)

instance Captures '[] 'SDK.StreamKind

instance Captures '[] 'SDK.ScopedKind

instance Captures '["TraceLine"] 'SDK.StreamKind where
  captureAt event = hookTraceLine event >> pure ()
  superWrap = SDK.superWith (captureAt @'["TraceLine"] @'SDK.StreamKind)

instance Captures '["TraceLine"] 'SDK.ScopedKind where
  captureAt event = hookTraceLine event >> pure ()
  superWrap = SDK.superWith (captureAt @'["TraceLine"] @'SDK.ScopedKind)
  closeWrap = SDK.superClosing (captureAt @'["TraceLine"] @'SDK.ScopedKind)


-- Middleware 的标签：handler 在这里执行，用 hook 读取触发本次调用的 Operation。
newtype Hook (effect :: FrameworkTypes.Symbol) value = Hook { runHook :: SDK.HookApp Effects.ContextValues Effects.Errors value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance SDK.Hooks (Hook "TraceLine") where
  hook = Hook SDK.currentOperation

instance SDK.RawOutputs (Hook "TraceLine")

instance SDK.Raises Effects.TraceLineError (Hook "TraceLine") where
  raise (Effects.TraceLineError description) = Hook (SDK.liftHookApp
    (SDK.failEffect "TraceLine" Effects.TraceLineFailure description))

hookTraceLine :: SDK.Operation -> Effects.App [String]
hookTraceLine event = SDK.runHookApp event (runHook @"TraceLine" (SDK.super "traceLine" Effects.traceLine))

instance SDK.Root (Hook effect) value

instance SDK.Root (Wrap hooks "Announce" method) value

instance SDK.Root (Wrap hooks "InputResource" method) value

instance Captures hooks 'SDK.ScopedKind => SDK.Root (Wrap hooks "InputSession" method) [String] where
  super name (Wrap action) = Wrap (superWrap @hooks @'SDK.ScopedKind name action)
  superClose name (Wrap action) = Wrap (closeWrap @hooks @'SDK.ScopedKind name action)

instance Captures hooks 'SDK.StreamKind => SDK.Root (Wrap hooks "LineFeed" method) () where
  super name (Wrap action) = Wrap (superWrap @hooks @'SDK.StreamKind name action)

instance SDK.Root (Wrap hooks "LineParser" method) value

instance SDK.Root (Wrap hooks "PrintLine" method) value

instance SDK.Root (Wrap hooks "TextCounter" method) value

instance SDK.Root (Wrap hooks "CountParser" method) value

instance SDK.Root (Wrap hooks "ShowTotal" method) value

instance SDK.Root (Wrap hooks "Report" method) value

instance SDK.Raises Effects.AnnounceError (Wrap hooks "Announce" method) where
  raise (Effects.AnnounceError description) = Wrap (SDK.failEffect "Announce" Effects.AnnounceFailure description)

instance SDK.Raises Effects.AcquireInputError (Wrap hooks "InputResource" method) where
  raise (Effects.AcquireInputError description) = Wrap (SDK.failEffect "InputResource" Effects.AcquireInputFailure description)

instance Captured hooks => SDK.Raises Effects.OpenInputError (Wrap hooks "InputSession" method) where
  raise (Effects.OpenInputError description) = Wrap (captureAt @hooks @'SDK.ScopedKind (SDK.Raise "openInput" description) >> SDK.failEffect "InputSession" Effects.OpenInputFailure description)

instance Captured hooks => SDK.Raises Effects.CloseInputError (Wrap hooks "InputSession" method) where
  raise (Effects.CloseInputError description) = Wrap (captureAt @hooks @'SDK.ScopedKind (SDK.Raise "closeInput" description) >> SDK.failEffect "InputSession" Effects.CloseInputFailure description)

instance Captured hooks => SDK.Raises Effects.NextLineError (Wrap hooks "LineFeed" method) where
  raise (Effects.NextLineError description) = Wrap (captureAt @hooks @'SDK.StreamKind (SDK.Raise "nextLine" description) >> SDK.failEffect "LineFeed" Effects.NextLineFailure description)

instance SDK.Raises Effects.ParseLineError (Wrap hooks "LineParser" method) where
  raise (Effects.ParseLineError description) = Wrap (SDK.failEffect "LineParser" Effects.ParseLineFailure description)

instance SDK.Raises Effects.PrintLineError (Wrap hooks "PrintLine" method) where
  raise (Effects.PrintLineError description) = Wrap (SDK.failEffect "PrintLine" Effects.PrintLineFailure description)

instance SDK.Raises Effects.CountTextError (Wrap hooks "TextCounter" method) where
  raise (Effects.CountTextError description) = Wrap (SDK.failEffect "TextCounter" Effects.CountTextFailure description)

instance SDK.Raises Effects.ParseTotalError (Wrap hooks "CountParser" method) where
  raise (Effects.ParseTotalError description) = Wrap (SDK.failEffect "CountParser" Effects.ParseTotalFailure description)

instance SDK.Raises Effects.ShowTotalError (Wrap hooks "ShowTotal" method) where
  raise (Effects.ShowTotalError description) = Wrap (SDK.failEffect "ShowTotal" Effects.ShowTotalFailure description)

instance SDK.Raises Effects.ReportError (Wrap hooks "Report" method) where
  raise (Effects.ReportError description) = Wrap (SDK.failEffect "Report" Effects.ReportFailure description)

instance SDK.Reads InputFile (Wrap hooks "InputSession" method) where
  require = Wrap (SDK.coerce <$> readOpenedInput)

instance SDK.Reads InputFile (Wrap hooks "LineFeed" method) where
  require = Wrap (SDK.coerce <$> readOpenedInput)

instance SDK.Reads Line (Wrap hooks "PrintLine" method) where
  require = Wrap (SDK.coerce <$> streamTextLine)

instance SDK.Reads Line (Wrap hooks "TextCounter" method) where
  require = Wrap (SDK.coerce <$> streamTextLine)

instance SDK.Reads InputFile (Wrap hooks "TextCounter" method) where
  require = Wrap (SDK.coerce <$> readOpenedInput)

instance SDK.Reads Total (Wrap hooks "ShowTotal" method) where
  require = Wrap (SDK.coerce <$> streamRunningTotal)

instance SDK.Reads Total (Wrap hooks "Report" method) where
  require = Wrap (SDK.coerce <$> streamRunningTotal)

instance Captured hooks => SDK.Raw (Wrap hooks "LineParser" method) where
  rawinput = Wrap (SDK.emittedInput >>= \value -> captureAt @hooks @'SDK.StreamKind (SDK.RawInput "parseLine" value) >> pure value)

instance Captured hooks => SDK.Raw (Wrap hooks "CountParser" method) where
  rawinput = Wrap (runTextCounter @hooks)

instance SDK.RawOutputs (Wrap hooks "Announce" "announce")

instance Captured hooks => SDK.RawOutputs (Wrap hooks "InputSession" "openInput") where
  rawoutput value = Wrap (captureAt @hooks @'SDK.ScopedKind (SDK.RawOutput "openInput" value) >> pure value)

instance Captured hooks => SDK.RawOutputs (Wrap hooks "InputSession" "closeInput") where
  rawoutput value = Wrap (captureAt @hooks @'SDK.ScopedKind (SDK.RawOutput "closeInput" value) >> pure value)

instance SDK.RawOutputs (Wrap hooks "PrintLine" "printLine")

instance SDK.RawOutputs (Wrap hooks "TextCounter" "countText")

instance SDK.RawOutputs (Wrap hooks "ShowTotal" "showTotal")

instance SDK.RawOutputs (Wrap hooks "Report" "report")

instance Captured hooks => SDK.Emits (Wrap hooks "LineFeed" method) where
  rawemit text = Wrap (captureAt @hooks @'SDK.StreamKind (SDK.RawEmit "nextLine" text) >> SDK.emitToParser text)

instance SDK.StreamEnds (Wrap hooks "LineFeed" method) where
  streamEnd = Wrap SDK.endSource

instance SDK.EndsStream (Wrap hooks "PrintLine" method) where
  endStream = Wrap SDK.endSubscription

instance SDK.EndsStream (Wrap hooks "TextCounter" method) where
  endStream = Wrap SDK.endSubscription

instance SDK.EndsStream (Wrap hooks "ShowTotal" method) where
  endStream = Wrap SDK.endSubscription

runAnnounce :: forall hooks. Captured hooks => Effects.App [String]
runAnnounce =
  SDK.handleFailure
  . SDK.atomicHandle "runAnnounce" [] []
  . SDK.enterHandler "Announce" $
    runWrap @hooks @"Announce" @"announce" (SDK.super "announce" Effects.announce)

getOpenedInput :: forall hooks. Captured hooks => Effects.App Effects.OpenedInput
getOpenedInput =
  SDK.handleFailure
  . SDK.callContext "InputResource"
      (\value bindings -> bindings { Effects.boundInputResource = Just value }) $
    Effects.OpenedInput <$> runWrap @hooks @"InputResource" @"acquireInput" (SDK.super "acquireInput" Effects.acquireInput)

readOpenedInput :: Effects.App Effects.OpenedInput
readOpenedInput =
  SDK.handleFailure $
    SDK.readContext "InputResource" Effects.ContextBindingError Effects.boundInputResource

openInputSession :: forall hooks. Captured hooks => Effects.App [String]
openInputSession =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.atomicScope "openInputSession" [] []
  . SDK.openScope "InputSession" Effects.ScopeBindingError (Just (() <$ closeInputSession @hooks))
  . SDK.enterHandler "InputSession" $
    getOpenedInput @hooks >> runWrap @hooks @"InputSession" @"openInput" (SDK.super "openInput" Effects.openInput)

closeInputSession :: forall hooks. Captured hooks => Effects.App [String]
closeInputSession =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.atomicScope "closeInputSession" [] []
  . SDK.closeScope "InputSession" Effects.ScopeBindingError
  . SDK.enterHandler "InputSession" $
    runWrap @hooks @"InputSession" @"closeInput" (SDK.superClose "closeInput" Effects.closeInput)

nextLineFeed :: forall hooks. Captured hooks => Effects.App ()
nextLineFeed =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["InputSession"]
  . SDK.enterHandler "LineFeed" $
    openInputSession @hooks >> runWrap @hooks @"LineFeed" @"nextLine" (SDK.super "nextLine" Effects.nextLine)

getTextLine :: forall hooks. Captured hooks => Effects.App Effects.TextLine
getTextLine =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["InputSession"]
  . SDK.callContext "LineParser"
      (\value bindings -> bindings { Effects.boundLineParser = Just value }) $
    Effects.TextLine <$> runWrap @hooks @"LineParser" @"parseLine" (SDK.super "parseLine" Effects.parseLine)

streamTextLine :: Effects.App Effects.TextLine
streamTextLine =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure $
    SDK.readStreamContext "LineParser" Effects.ContextBindingError Effects.boundLineParser

runPrintLine :: forall hooks. Captured hooks => Effects.App [String]
runPrintLine =
  SDK.handleFailure
  . SDK.atomicHandle "runPrintLine" [] []
  . SDK.enterHandler "PrintLine" $
    runWrap @hooks @"PrintLine" @"printLine" (SDK.super "printLine" Effects.printLine)

runTextCounter :: forall hooks. Captured hooks => Effects.App [String]
runTextCounter =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runTextCounter" [] [("CountParser", () <$ getRunningTotal @hooks)]
  . SDK.withScopeDependencies ["InputSession"]
  . SDK.enterHandler "TextCounter" $
    openInputSession @hooks >> runWrap @hooks @"TextCounter" @"countText" (SDK.super "countText" Effects.countText)

getRunningTotal :: forall hooks. Captured hooks => Effects.App Effects.RunningTotal
getRunningTotal =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["InputSession"]
  . SDK.callContext "CountParser"
      (\value bindings -> bindings { Effects.boundCountParser = Just value }) $
    Effects.RunningTotal <$> runWrap @hooks @"CountParser" @"parseTotal" (SDK.super "parseTotal" Effects.parseTotal)

streamRunningTotal :: Effects.App Effects.RunningTotal
streamRunningTotal =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure $
    SDK.readStreamContext "CountParser" Effects.ContextBindingError Effects.boundCountParser

runShowTotal :: forall hooks. Captured hooks => Effects.App [String]
runShowTotal =
  SDK.handleFailure
  . SDK.atomicHandle "runShowTotal" [] []
  . SDK.enterHandler "ShowTotal" $
    runWrap @hooks @"ShowTotal" @"showTotal" (SDK.super "showTotal" Effects.showTotal)

runReport :: forall hooks. Captured hooks => Effects.App [String]
runReport =
  SDK.handleFailure
  . SDK.atomicHandle "runReport" [] []
  . SDK.enterHandler "Report" $
    runWrap @hooks @"Report" @"report" (SDK.super "report" Effects.report)

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler "InputSession" [] (Just "InputResource")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
