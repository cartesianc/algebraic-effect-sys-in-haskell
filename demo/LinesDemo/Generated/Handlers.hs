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

import qualified Framework.Generated as FrameworkRuntime
import qualified LinesDemo.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import LinesDemo.Types
import Framework.SDK (Emits(rawemit), Hooks(..), StreamEnds(..), Raises(..), Raw(..), Reads(..), rawoutput)
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
    rawinputhook $ \parser fields -> liftIO (putStrLn ("[input] " ++ parser ++ ": " ++ show fields))
    rawoutputhook $ \handler fields -> liftIO (putStrLn ("[output] " ++ handler ++ ": " ++ show fields))
    rawemithook $ \source line -> liftIO (putStrLn ("[emit] " ++ source ++ ": " ++ line))
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
handlerSourceFingerprint = Just "caef51f83e8bc32dadd1871a9ffe6aa6"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (hooks :: [FrameworkTypes.Symbol]) (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = Wrap { runWrap :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

-- superhandler 的静态选择：hooks 是覆盖本次挂载的 Middleware（注册顺序），kind 是捕获类别。
-- 默认方法即空选择：不捕获，super 直接执行 action。
class Captures (hooks :: [FrameworkTypes.Symbol]) (kind :: FrameworkRuntime.EffectKind) where
  captureAt :: FrameworkRuntime.HookEvent -> FrameworkGenerated.App ()
  captureAt _ = pure ()
  superWrap, closeWrap :: String -> FrameworkGenerated.App [String] -> FrameworkGenerated.App [String]
  superWrap _ = id
  closeWrap _ = id

-- 入口对 hooks 多态：每个被拦截的类别都有该列表的选择。
type Captured hooks = (Captures hooks 'FrameworkRuntime.StreamKind, Captures hooks 'FrameworkRuntime.ScopedKind)

instance Captures '[] 'FrameworkRuntime.StreamKind

instance Captures '[] 'FrameworkRuntime.ScopedKind

instance Captures '["TraceLine"] 'FrameworkRuntime.StreamKind where
  captureAt event = hookTraceLine event >> pure ()

instance Captures '["TraceLine"] 'FrameworkRuntime.ScopedKind where
  captureAt event = hookTraceLine event >> pure ()
  superWrap = FrameworkRuntime.superWith (captureAt @'["TraceLine"] @'FrameworkRuntime.ScopedKind)
  closeWrap = FrameworkRuntime.superClosing (captureAt @'["TraceLine"] @'FrameworkRuntime.ScopedKind)


-- Middleware 的标签：handler 在这里执行，用 hooked* 读本次调用点捕获的 (handler 名, 值)。
newtype Hook (effect :: FrameworkTypes.Symbol) value = Hook { runHook :: FrameworkRuntime.HookApp FrameworkGenerated.ContextValues FrameworkGenerated.Errors value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkRuntime.Hooks (Hook "TraceLine") where
  hookedEnter = Hook FrameworkRuntime.hookEnter
  hookedOutput = Hook FrameworkRuntime.hookOutput
  hookedRaw = Hook FrameworkRuntime.hookRaw
  hookedError = Hook FrameworkRuntime.hookError
  rawoutputhook action = Hook (FrameworkRuntime.onRawOutput (\name value -> runHook (action name value)))
  rawemithook action = Hook (FrameworkRuntime.onEmit (\name value -> runHook (action name value)))

instance FrameworkRuntime.RawOutputs (Hook "TraceLine")

instance FrameworkRuntime.Raises FrameworkGenerated.TraceLineError (Hook "TraceLine") where
  raise (FrameworkGenerated.TraceLineError description) = Hook (FrameworkRuntime.liftHookApp
    (FrameworkRuntime.failEffect "TraceLine" FrameworkGenerated.TraceLineFailure description))

hookTraceLine :: FrameworkRuntime.HookEvent -> FrameworkGenerated.App [String]
hookTraceLine event = FrameworkRuntime.runHookApp event (runHook @"TraceLine" (FrameworkRuntime.super "traceLine" FrameworkGenerated.traceLine))

instance FrameworkRuntime.Root (Hook effect) value

instance FrameworkRuntime.Root (Wrap hooks "Announce" method) value

instance FrameworkRuntime.Root (Wrap hooks "InputResource" method) value

instance Captures hooks 'FrameworkRuntime.ScopedKind => FrameworkRuntime.Root (Wrap hooks "InputSession" method) [String] where
  super name (Wrap action) = Wrap (superWrap @hooks @'FrameworkRuntime.ScopedKind name action)
  superClose name (Wrap action) = Wrap (closeWrap @hooks @'FrameworkRuntime.ScopedKind name action)

instance Captures hooks 'FrameworkRuntime.StreamKind => FrameworkRuntime.Root (Wrap hooks "LineFeed" method) () where
  super name (Wrap action) = Wrap (captureAt @hooks @'FrameworkRuntime.StreamKind (FrameworkRuntime.EnterEvent name) >> action)

instance FrameworkRuntime.Root (Wrap hooks "LineParser" method) value

instance FrameworkRuntime.Root (Wrap hooks "PrintLine" method) value

instance FrameworkRuntime.Root (Wrap hooks "TextCounter" method) value

instance FrameworkRuntime.Root (Wrap hooks "CountParser" method) value

instance FrameworkRuntime.Root (Wrap hooks "ShowTotal" method) value

instance FrameworkRuntime.Root (Wrap hooks "Report" method) value

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.AnnounceError (Wrap hooks "Announce" method) where
  raise (FrameworkGenerated.AnnounceError description) = Wrap (FrameworkRuntime.failEffect "Announce" FrameworkGenerated.AnnounceFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.AcquireInputError (Wrap hooks "InputResource" method) where
  raise (FrameworkGenerated.AcquireInputError description) = Wrap (FrameworkRuntime.failEffect "InputResource" FrameworkGenerated.AcquireInputFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.OpenInputError (Wrap hooks "InputSession" method) where
  raise (FrameworkGenerated.OpenInputError description) = Wrap (captureAt @hooks @'FrameworkRuntime.ScopedKind (FrameworkRuntime.ErrorEvent "openInput" description) >> FrameworkRuntime.failEffect "InputSession" FrameworkGenerated.OpenInputFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.CloseInputError (Wrap hooks "InputSession" method) where
  raise (FrameworkGenerated.CloseInputError description) = Wrap (captureAt @hooks @'FrameworkRuntime.ScopedKind (FrameworkRuntime.ErrorEvent "closeInput" description) >> FrameworkRuntime.failEffect "InputSession" FrameworkGenerated.CloseInputFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.NextLineError (Wrap hooks "LineFeed" method) where
  raise (FrameworkGenerated.NextLineError description) = Wrap (captureAt @hooks @'FrameworkRuntime.StreamKind (FrameworkRuntime.ErrorEvent "nextLine" description) >> FrameworkRuntime.failEffect "LineFeed" FrameworkGenerated.NextLineFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.ParseLineError (Wrap hooks "LineParser" method) where
  raise (FrameworkGenerated.ParseLineError description) = Wrap (FrameworkRuntime.failEffect "LineParser" FrameworkGenerated.ParseLineFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.PrintLineError (Wrap hooks "PrintLine" method) where
  raise (FrameworkGenerated.PrintLineError description) = Wrap (FrameworkRuntime.failEffect "PrintLine" FrameworkGenerated.PrintLineFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.CountTextError (Wrap hooks "TextCounter" method) where
  raise (FrameworkGenerated.CountTextError description) = Wrap (FrameworkRuntime.failEffect "TextCounter" FrameworkGenerated.CountTextFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.ParseTotalError (Wrap hooks "CountParser" method) where
  raise (FrameworkGenerated.ParseTotalError description) = Wrap (FrameworkRuntime.failEffect "CountParser" FrameworkGenerated.ParseTotalFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.ShowTotalError (Wrap hooks "ShowTotal" method) where
  raise (FrameworkGenerated.ShowTotalError description) = Wrap (FrameworkRuntime.failEffect "ShowTotal" FrameworkGenerated.ShowTotalFailure description)

instance Captured hooks => FrameworkRuntime.Raises FrameworkGenerated.ReportError (Wrap hooks "Report" method) where
  raise (FrameworkGenerated.ReportError description) = Wrap (FrameworkRuntime.failEffect "Report" FrameworkGenerated.ReportFailure description)

instance FrameworkRuntime.Reads (InputFile) (Wrap hooks "InputSession" method) where
  require = Wrap ((\(FrameworkGenerated.OpenedInput value) -> value) <$> readOpenedInput)

instance FrameworkRuntime.Reads (InputFile) (Wrap hooks "LineFeed" method) where
  require = Wrap ((\(FrameworkGenerated.OpenedInput value) -> value) <$> readOpenedInput)

instance FrameworkRuntime.Reads (Line) (Wrap hooks "PrintLine" method) where
  require = Wrap ((\(FrameworkGenerated.TextLine value) -> value) <$> streamTextLine)

instance FrameworkRuntime.Reads (Line) (Wrap hooks "TextCounter" method) where
  require = Wrap ((\(FrameworkGenerated.TextLine value) -> value) <$> streamTextLine)

instance FrameworkRuntime.Reads (InputFile) (Wrap hooks "TextCounter" method) where
  require = Wrap ((\(FrameworkGenerated.OpenedInput value) -> value) <$> readOpenedInput)

instance FrameworkRuntime.Reads (Total) (Wrap hooks "ShowTotal" method) where
  require = Wrap ((\(FrameworkGenerated.RunningTotal value) -> value) <$> streamRunningTotal)

instance FrameworkRuntime.Reads (Total) (Wrap hooks "Report" method) where
  require = Wrap ((\(FrameworkGenerated.RunningTotal value) -> value) <$> streamRunningTotal)

instance Captured hooks => FrameworkRuntime.Raw (Wrap hooks "LineParser" method) where
  rawinput = Wrap (FrameworkRuntime.emittedInput >>= \value -> captureAt @hooks @'FrameworkRuntime.StreamKind (FrameworkRuntime.RawEvent "parseLine" value) >> pure value)

instance Captured hooks => FrameworkRuntime.Raw (Wrap hooks "CountParser" method) where
  rawinput = Wrap (runTextCounter @hooks)

instance Captured hooks => FrameworkRuntime.RawOutputs (Wrap hooks "Announce" "announce") where
  rawoutput value = Wrap (pure value)

instance Captured hooks => FrameworkRuntime.RawOutputs (Wrap hooks "InputSession" "openInput") where
  rawoutput value = Wrap (captureAt @hooks @'FrameworkRuntime.ScopedKind (FrameworkRuntime.RawOutputEvent "openInput" value) >> pure value)

instance Captured hooks => FrameworkRuntime.RawOutputs (Wrap hooks "InputSession" "closeInput") where
  rawoutput value = Wrap (captureAt @hooks @'FrameworkRuntime.ScopedKind (FrameworkRuntime.RawOutputEvent "closeInput" value) >> pure value)

instance Captured hooks => FrameworkRuntime.RawOutputs (Wrap hooks "PrintLine" "printLine") where
  rawoutput value = Wrap (pure value)

instance Captured hooks => FrameworkRuntime.RawOutputs (Wrap hooks "TextCounter" "countText") where
  rawoutput value = Wrap (pure value)

instance Captured hooks => FrameworkRuntime.RawOutputs (Wrap hooks "ShowTotal" "showTotal") where
  rawoutput value = Wrap (pure value)

instance Captured hooks => FrameworkRuntime.RawOutputs (Wrap hooks "Report" "report") where
  rawoutput value = Wrap (pure value)

instance Captured hooks => FrameworkRuntime.Emits (Wrap hooks "LineFeed" method) where
  rawemit text = Wrap (captureAt @hooks @'FrameworkRuntime.StreamKind (FrameworkRuntime.EmitEvent "nextLine" text) >> FrameworkRuntime.emitToParser text)

instance FrameworkRuntime.StreamEnds (Wrap hooks "LineFeed" method) where
  streamEnd = Wrap FrameworkRuntime.endSource

instance FrameworkRuntime.EndsStream (Wrap hooks "PrintLine" method) where
  endStream = Wrap FrameworkRuntime.endSubscription

instance FrameworkRuntime.EndsStream (Wrap hooks "TextCounter" method) where
  endStream = Wrap FrameworkRuntime.endSubscription

instance FrameworkRuntime.EndsStream (Wrap hooks "ShowTotal" method) where
  endStream = Wrap FrameworkRuntime.endSubscription

runAnnounce :: forall hooks. Captured hooks => FrameworkGenerated.App [String]
runAnnounce = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runAnnounce" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "Announce") $
  runWrap @hooks @"Announce" @"announce" (FrameworkRuntime.super "announce" FrameworkGenerated.announce)

getOpenedInput :: forall hooks. Captured hooks => FrameworkGenerated.App FrameworkGenerated.OpenedInput
getOpenedInput = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "InputResource"
    (\value bindings -> bindings { FrameworkGenerated.boundInputResource = Just value })) $
  (FrameworkGenerated.OpenedInput <$> runWrap @hooks @"InputResource" @"acquireInput" (FrameworkRuntime.super "acquireInput" FrameworkGenerated.acquireInput))

readOpenedInput :: FrameworkGenerated.App FrameworkGenerated.OpenedInput
readOpenedInput = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "InputResource" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundInputResource

openInputSession :: forall hooks. Captured hooks => FrameworkGenerated.App [String]
openInputSession = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openInputSession" [] [] . FrameworkRuntime.openScope "InputSession" FrameworkGenerated.ScopeBindingError (Just (() <$ closeInputSession @hooks)) . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "InputSession") $
  getOpenedInput @hooks >> runWrap @hooks @"InputSession" @"openInput" (FrameworkRuntime.super "openInput" FrameworkGenerated.openInput)

closeInputSession :: forall hooks. Captured hooks => FrameworkGenerated.App [String]
closeInputSession = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeInputSession" [] [] . FrameworkRuntime.closeScope "InputSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "InputSession") $
  runWrap @hooks @"InputSession" @"closeInput" (FrameworkRuntime.superClose "closeInput" FrameworkGenerated.closeInput)

nextLineFeed :: forall hooks. Captured hooks => FrameworkGenerated.App ()
nextLineFeed = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["InputSession"] . FrameworkRuntime.enterHandler "LineFeed") $
  openInputSession @hooks >> runWrap @hooks @"LineFeed" @"nextLine" (FrameworkRuntime.super "nextLine" FrameworkGenerated.nextLine)

getTextLine :: forall hooks. Captured hooks => FrameworkGenerated.App FrameworkGenerated.TextLine
getTextLine = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["InputSession"] . FrameworkRuntime.callContext "LineParser"
    (\value bindings -> bindings { FrameworkGenerated.boundLineParser = Just value })) $
  (FrameworkGenerated.TextLine <$> runWrap @hooks @"LineParser" @"parseLine" (FrameworkRuntime.super "parseLine" FrameworkGenerated.parseLine))

streamTextLine :: FrameworkGenerated.App FrameworkGenerated.TextLine
streamTextLine = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readStreamContext "LineParser" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundLineParser

runPrintLine :: forall hooks. Captured hooks => FrameworkGenerated.App [String]
runPrintLine = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runPrintLine" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "PrintLine") $
  runWrap @hooks @"PrintLine" @"printLine" (FrameworkRuntime.super "printLine" FrameworkGenerated.printLine)

runTextCounter :: forall hooks. Captured hooks => FrameworkGenerated.App [String]
runTextCounter = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runTextCounter" [] [("CountParser", () <$ getRunningTotal @hooks)] . FrameworkRuntime.withScopeDependencies ["InputSession"] . FrameworkRuntime.enterHandler "TextCounter") $
  openInputSession @hooks >> runWrap @hooks @"TextCounter" @"countText" (FrameworkRuntime.super "countText" FrameworkGenerated.countText)

getRunningTotal :: forall hooks. Captured hooks => FrameworkGenerated.App FrameworkGenerated.RunningTotal
getRunningTotal = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["InputSession"] . FrameworkRuntime.callContext "CountParser"
    (\value bindings -> bindings { FrameworkGenerated.boundCountParser = Just value })) $
  (FrameworkGenerated.RunningTotal <$> runWrap @hooks @"CountParser" @"parseTotal" (FrameworkRuntime.super "parseTotal" FrameworkGenerated.parseTotal))

streamRunningTotal :: FrameworkGenerated.App FrameworkGenerated.RunningTotal
streamRunningTotal = (FrameworkRuntime.withErrorPath ["InputSession"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readStreamContext "CountParser" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundCountParser

runShowTotal :: forall hooks. Captured hooks => FrameworkGenerated.App [String]
runShowTotal = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runShowTotal" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "ShowTotal") $
  runWrap @hooks @"ShowTotal" @"showTotal" (FrameworkRuntime.super "showTotal" FrameworkGenerated.showTotal)

runReport :: forall hooks. Captured hooks => FrameworkGenerated.App [String]
runReport = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReport" [] [] . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "Report") $
  runWrap @hooks @"Report" @"report" (FrameworkRuntime.super "report" FrameworkGenerated.report)

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "InputSession" [] (Just "InputResource")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [
  ]
