-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeOperators #-}
-- handler 是不带参数的类方法；SDK 按注册装配上游、会话与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module LinesDemo.Generated.Handlers (handlerSourceFingerprint, runAnnounce, getOpenedInput, readOpenedInput, openInputSession, closeInputSession, nextLineFeed, hookTraceLine, getTextLine, streamTextLine, runPrintLine, runTextCounter, getRunningTotal, streamRunningTotal, runShowTotal, runReport, historyTextLine, historyRunningTotal, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified LinesDemo.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Emits(rawemit), Hooks(hook), Operation(..), StreamEnds(..), Raises(..), Raw(..), Reads(..), Streams(..), rawoutput)
import LinesDemo.Generated.Effects
import LinesDemo.Types
import Control.Monad.Catch (bracket)
import Control.Monad.IO.Class (liftIO)
import Data.Foldable (toList)
import System.FilePath ((</>))
import System.IO (IOMode(ReadMode), hClose, hGetLine, hIsEOF, openFile)

instance AnnounceLayer m => AnnounceHandler m where
  announce = do
    liftIO (putStrLn "Reading the input line by line.")
    rawoutput []

-- 输入文件在第一次读行时由 InputSession 取得；资产只记路径。
instance AcquireInputLayer m => AcquireInputHandler m where
  acquireInput = do
    let path = "demo" </> "LinesDemo" </> "input.txt"
    pure (InputFile path)

instance OpenInputLayer m => OpenInputHandler m where
  openInput = do
    InputFile path <- require @InputFile
    liftIO (putStrLn ("[open] " ++ path))
    rawoutput []

instance CloseInputLayer m => CloseInputHandler m where
  closeInput = do
    InputFile path <- require @InputFile
    liftIO (putStrLn ("[close] " ++ path))
    rawoutput []

-- 在一次来源调用内持续读取。文件句柄由这次调用自己打开和关闭；每个 rawemit 都完成这行的解析与发布，再读取下一行。
instance NextLineLayer m => NextLineHandler m where
  nextLine = do
    InputFile path <- require @InputFile
    bracket (liftIO (openFile path ReadMode)) (liftIO . hClose) $ \file -> do
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

-- 由 TextLine 驱动：每来一行执行一次。stream 给出本次的一行及同一会话中更早的行，计数直接由它算出。
instance CountTextLayer m => CountTextHandler m where
  countText = do
    seen <- stream @Line
    rawoutput [show (length seen), show (sum [length text | Line text <- toList seen])]

instance ParseTotalLayer m => ParseTotalHandler m where
  parseTotal = do
    fields <- rawinput
    case fields of
      [count, size] -> pure (Total count size)
      _ -> raise (ParseTotalError "the counter gives a line count and a character count")

instance ShowTotalLayer m => ShowTotalHandler m where
  showTotal = do
    Total count size <- require @Total
    liftIO (putStrLn ("  so far: " ++ count ++ " lines, " ++ size ++ " characters"))
    rawoutput []

instance ReportLayer m => ReportHandler m where
  report = do
    Total count size <- require @Total
    liftIO (putStrLn ("The selected total is: " ++ count ++ " lines, " ++ size ++ " characters."))
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "3f39278c48136875b3662ba3ff377477"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (hooks :: [FrameworkTypes.Symbol]) (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO, SDK.MonadThrow, SDK.MonadCatch, SDK.MonadMask)

-- 类型标签上的名字：effect 名与方法名只写在标签上，需要字符串时从这里取。
nameOf :: forall name. FrameworkTypes.KnownSymbol name => String
nameOf = FrameworkTypes.symbolVal (FrameworkProxy.Proxy @name)

-- 在标签下执行 handler，交给 Root 的 superhandler；方法名取自标签。close 的调用点用 callClose。
call :: forall hooks effect method kind value. (FrameworkTypes.KnownSymbol method, KindOf effect kind, Captures hooks kind)
  => Wrap hooks effect method value -> Effects.App value
call handler = runWrap (SDK.super (nameOf @method) handler)

callClose :: forall hooks effect method kind value. (FrameworkTypes.KnownSymbol method, KindOf effect kind, Captures hooks kind)
  => Wrap hooks effect method value -> Effects.App value
callClose handler = runWrap (SDK.superClose (nameOf @method) handler)

-- 每个 effect 的类别：Root 与显式操作按它取 Captures 的选择。
class KindOf (effect :: FrameworkTypes.Symbol) (kind :: SDK.EffectKind) | effect -> kind
instance KindOf "Announce" 'SDK.ExcuKind
instance KindOf "InputResource" 'SDK.ContextKind
instance KindOf "InputSession" 'SDK.ScopedKind
instance KindOf "LineFeed" 'SDK.StreamKind
instance KindOf "LineParser" 'SDK.ContextKind
instance KindOf "PrintLine" 'SDK.ExcuKind
instance KindOf "TextCounter" 'SDK.ExcuKind
instance KindOf "CountParser" 'SDK.ContextKind
instance KindOf "ShowTotal" 'SDK.ExcuKind
instance KindOf "Report" 'SDK.ExcuKind

-- superhandler 的静态选择：hooks 是覆盖本次挂载的 Middleware（注册顺序），kind 是捕获类别。
-- 默认即空选择：不捕获，super 直接执行 action。
class Captures (hooks :: [FrameworkTypes.Symbol]) (kind :: SDK.EffectKind) where
  selected :: Maybe (SDK.Operation -> Effects.App ())
  selected = Nothing

-- 入口对 hooks 多态：每个被拦截的类别都有该列表的选择。
type Captured hooks = (Captures hooks 'SDK.StreamKind, Captures hooks 'SDK.ScopedKind)

instance Captures '[] 'SDK.StreamKind
instance Captures '[] 'SDK.ScopedKind
instance Captures '["TraceLine"] 'SDK.StreamKind where
  selected = Just (\event -> hookTraceLine event >> pure ())
instance Captures '["TraceLine"] 'SDK.ScopedKind where
  selected = Just (\event -> hookTraceLine event >> pure ())
instance Captures hooks 'SDK.ExcuKind
instance Captures hooks 'SDK.ContextKind

selection :: forall hooks effect kind. (KindOf effect kind, Captures hooks kind)
  => Maybe (SDK.Operation -> Effects.App ())
selection = selected @hooks @kind

-- 显式操作的捕获点：把本 handler 的操作交给选中的 Middleware，操作名取自标签。
notifyAt :: forall kind hooks effect method. (Captures hooks kind, FrameworkTypes.KnownSymbol method)
  => (String -> SDK.Operation) -> Wrap hooks effect method ()
notifyAt event = Wrap (maybe (pure ()) ($ event (nameOf @method)) (selected @hooks @kind))

notify :: forall hooks effect method kind. (KindOf effect kind, Captures hooks kind, FrameworkTypes.KnownSymbol method)
  => (String -> SDK.Operation) -> Wrap hooks effect method ()
notify = notifyAt @kind

-- Middleware 的标签：handler 在这里执行，用 hook 读取触发本次调用的 Operation。
newtype Hook (effect :: FrameworkTypes.Symbol) value = Hook { runHook :: SDK.HookApp Effects.ContextValues Effects.Errors value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance SDK.Hooks (Hook effect) where
  hook = Hook SDK.currentOperation

instance SDK.RawOutputs (Hook effect)

instance (SDK.HandlerError problem Effects.Errors, FrameworkTypes.KnownSymbol effect)
    => SDK.Raises problem (Hook effect) where
  raise problem = Hook (SDK.liftHookApp (SDK.failEffect (nameOf @effect) failure description))
    where (failure, description) = SDK.raised problem

hookTraceLine :: SDK.Operation -> Effects.App [String]
hookTraceLine event = SDK.runHookApp event (runHook @"TraceLine" (SDK.super "traceLine" Effects.traceLine))

instance SDK.Root (Hook effect) value

instance (KindOf effect kind, Captures hooks kind) => SDK.Root (Wrap hooks effect method) value where
  super name (Wrap action) = Wrap (maybe (const id) SDK.superWith (selection @hooks @effect) name action)
  superClose name (Wrap action) = Wrap (maybe (const id) SDK.superClosing (selection @hooks @effect) name action)

instance (SDK.HandlerError problem Effects.Errors, FrameworkTypes.KnownSymbol effect
         , KindOf effect kind, Captures hooks kind, FrameworkTypes.KnownSymbol method)
    => SDK.Raises problem (Wrap hooks effect method) where
  raise problem = notify (`SDK.Raise` description) >> Wrap (SDK.failEffect (nameOf @effect) failure description)
    where (failure, description) = SDK.raised problem

instance SDK.Reads InputFile (Wrap hooks "InputSession" method) where
  require = Wrap (SDK.coerce <$> readOpenedInput)

instance SDK.Reads InputFile (Wrap hooks "LineFeed" method) where
  require = Wrap (SDK.coerce <$> readOpenedInput)

instance SDK.Reads Line (Wrap hooks "PrintLine" method) where
  require = Wrap (SDK.coerce <$> streamTextLine)

instance SDK.Reads Line (Wrap hooks "TextCounter" method) where
  require = Wrap (SDK.coerce <$> streamTextLine)

instance SDK.Reads Total (Wrap hooks "ShowTotal" method) where
  require = Wrap (SDK.coerce <$> streamRunningTotal)

instance SDK.Reads Total (Wrap hooks "Report" method) where
  require = Wrap (SDK.coerce <$> streamRunningTotal)

instance SDK.Streams Line (Wrap hooks "PrintLine" method) where
  stream = Wrap (SDK.coerce <$> historyTextLine)

instance SDK.Streams Line (Wrap hooks "TextCounter" method) where
  stream = Wrap (SDK.coerce <$> historyTextLine)

instance SDK.Streams Total (Wrap hooks "ShowTotal" method) where
  stream = Wrap (SDK.coerce <$> historyRunningTotal)

instance Captured hooks => SDK.Raw (Wrap hooks "LineParser" "parseLine") where
  rawinput = Wrap SDK.emittedInput >>= \value -> value <$ notifyAt @'SDK.StreamKind (`SDK.RawInput` value)

instance Captured hooks => SDK.Raw (Wrap hooks "CountParser" "parseTotal") where
  rawinput = Wrap (runTextCounter @hooks)

instance (KindOf effect kind, Captures hooks kind, FrameworkTypes.KnownSymbol method) => SDK.RawOutputs (Wrap hooks effect method) where
  rawoutput value = value <$ notify (`SDK.RawOutput` value)

instance (KindOf effect kind, Captures hooks kind, FrameworkTypes.KnownSymbol method) => SDK.Emits (Wrap hooks effect method) where
  rawemit text = notify (`SDK.RawEmit` text) >> Wrap (SDK.emitToParser text)

instance SDK.StreamEnds (Wrap hooks effect method) where
  streamEnd = Wrap SDK.endSource

instance SDK.EndsStream (Wrap hooks effect method) where
  endStream = Wrap SDK.endSubscription

runAnnounce :: forall hooks. Captured hooks => Effects.App [String]
runAnnounce =
  SDK.handleFailure
  . SDK.atomicHandle "runAnnounce" []
  . SDK.enterHandler (SDK.Slot 0 "Announce") $
    call @hooks @"Announce" @"announce" Effects.announce

getOpenedInput :: forall hooks. Captured hooks => Effects.App Effects.OpenedInput
getOpenedInput =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 1 "InputResource")
      (\value bindings -> bindings { Effects.boundInputResource = Just value }) $
    Effects.OpenedInput <$> call @hooks @"InputResource" @"acquireInput" Effects.acquireInput

readOpenedInput :: Effects.App Effects.OpenedInput
readOpenedInput =
  SDK.handleFailure $
    SDK.readContext (SDK.Slot 1 "InputResource") Effects.ContextBindingError Effects.boundInputResource

openInputSession :: forall hooks. Captured hooks => Effects.App [String]
openInputSession =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.atomicScope "openInputSession" []
  . SDK.openScope "InputSession" Effects.ScopeBindingError (Just (() <$ closeInputSession @hooks))
  . SDK.enterHandler (SDK.Slot 2 "InputSession") $
    getOpenedInput @hooks >> call @hooks @"InputSession" @"openInput" Effects.openInput

closeInputSession :: forall hooks. Captured hooks => Effects.App [String]
closeInputSession =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.atomicScope "closeInputSession" []
  . SDK.closeScope "InputSession" Effects.ScopeBindingError
  . SDK.enterHandler (SDK.Slot 2 "InputSession") $
    callClose @hooks @"InputSession" @"closeInput" Effects.closeInput

nextLineFeed :: forall hooks. Captured hooks => Effects.App ()
nextLineFeed =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["InputSession"]
  . SDK.enterHandler (SDK.Slot 3 "LineFeed") $
    openInputSession @hooks >> call @hooks @"LineFeed" @"nextLine" Effects.nextLine

getTextLine :: forall hooks. Captured hooks => Effects.App Effects.TextLine
getTextLine =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["InputSession"]
  . SDK.callContext (SDK.Slot 5 "LineParser")
      (\value bindings -> bindings { Effects.boundLineParser = Just value }) $
    Effects.TextLine <$> call @hooks @"LineParser" @"parseLine" Effects.parseLine

streamTextLine :: Effects.App Effects.TextLine
streamTextLine =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure $
    SDK.readStreamContext (SDK.Slot 5 "LineParser") Effects.ContextBindingError Effects.boundLineParser

historyTextLine :: Effects.App (SDK.Flow Effects.TextLine)
historyTextLine =
  SDK.withErrorPath ["InputSession"]
  . SDK.handleFailure $
    SDK.readStreamHistory (SDK.Slot 5 "LineParser") Effects.ContextBindingError Effects.boundLineParser

runPrintLine :: forall hooks. Captured hooks => Effects.App [String]
runPrintLine =
  SDK.handleFailure
  . SDK.atomicHandle "runPrintLine" []
  . SDK.enterHandler (SDK.Slot 6 "PrintLine") $
    call @hooks @"PrintLine" @"printLine" Effects.printLine

runTextCounter :: forall hooks. Captured hooks => Effects.App [String]
runTextCounter =
  SDK.handleFailure
  . SDK.atomicHandle "runTextCounter" [((SDK.Slot 8 "CountParser"), () <$ getRunningTotal @hooks)]
  . SDK.enterHandler (SDK.Slot 7 "TextCounter") $
    call @hooks @"TextCounter" @"countText" Effects.countText

getRunningTotal :: forall hooks. Captured hooks => Effects.App Effects.RunningTotal
getRunningTotal =
  SDK.handleFailure
  . SDK.callContext (SDK.Slot 8 "CountParser")
      (\value bindings -> bindings { Effects.boundCountParser = Just value }) $
    Effects.RunningTotal <$> call @hooks @"CountParser" @"parseTotal" Effects.parseTotal

streamRunningTotal :: Effects.App Effects.RunningTotal
streamRunningTotal =
  SDK.handleFailure $
    SDK.readStreamContext (SDK.Slot 8 "CountParser") Effects.ContextBindingError Effects.boundCountParser

historyRunningTotal :: Effects.App (SDK.Flow Effects.RunningTotal)
historyRunningTotal =
  SDK.handleFailure $
    SDK.readStreamHistory (SDK.Slot 8 "CountParser") Effects.ContextBindingError Effects.boundCountParser

runShowTotal :: forall hooks. Captured hooks => Effects.App [String]
runShowTotal =
  SDK.handleFailure
  . SDK.atomicHandle "runShowTotal" []
  . SDK.enterHandler (SDK.Slot 9 "ShowTotal") $
    call @hooks @"ShowTotal" @"showTotal" Effects.showTotal

runReport :: forall hooks. Captured hooks => Effects.App [String]
runReport =
  SDK.handleFailure
  . SDK.atomicHandle "runReport" []
  . SDK.enterHandler (SDK.Slot 10 "Report") $
    call @hooks @"Report" @"report" Effects.report

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler (SDK.Slot 2 "InputSession") [] (Just (SDK.Slot 1 "InputResource"))
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers = []
