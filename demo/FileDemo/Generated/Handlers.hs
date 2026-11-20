-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- 上游、scope 和资产名都不出现在这里；gen 按注册装配，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FileDemo.Generated.Handlers (handlerSourceFingerprint, runLocateFile, runValidateFileName, getFileName, readFileName, getOpenedFile, readOpenedFile, openFileSession, closeFileSession, detectFileRecovery, resolveFileRecovery, runReadFile, getFileText, readFileText, runWriteFirstLine, runAppendLine, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified FileDemo.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Raises(..), Raw(..), Reads(..), rawoutput)
import FileDemo.Generated.Effects
import FileDemo.Types
import Control.Exception (bracketOnError, displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Function (fix)
import System.FilePath ((</>))
import System.IO
  ( IOMode(ReadWriteMode), SeekMode(AbsoluteSeek, SeekFromEnd)
  , hClose, hFlush, hGetChar, hIsClosed, hIsEOF, hPutStr, hSeek, hSetEncoding
  , openFile, utf8 )
import System.IO.Error (tryIOError)

-- 示例专用文件：首次运行创建，后续追加；在项目根目录运行。原子句柄交出路径 list。
instance LocateFileLayer m => LocateFileHandler m where
  locateFile = rawoutput ["demo" </> "FileDemo" </> "output.txt"]

-- Pure：rawinput 是上层交出的路径 list；逐项检查后原样交给下面的 parser。没有 IO，也不读资产。
instance ValidateFileNameLayer m => ValidateFileNameHandler m where
  validateFileName = do
    paths <- rawinput
    unless (all (\path -> not (null path) && '\0' `notElem` path) paths) $
      raise (ValidateFileNameError "File name must be nonempty and contain no NUL character")
    rawoutput paths

-- Context 是细化 parser：通过检查的 list 恰好有一个路径时，才是文件名资产。
instance ParseFileNameLayer m => ParseFileNameHandler m where
  parseFileName = do
    paths <- rawinput
    case paths of
      [path] -> pure path
      _ -> raise (ParseFileNameError "Expected exactly one file name")

-- 文件名由 requests 驱动，生产时已经过 ValidateFileName 的检查。
instance AcquireFileLayer m => AcquireFileHandler m where
  acquireFile = do
    path <- require @FilePath
    outcome <- liftIO $ tryIOError $
      bracketOnError (openFile path ReadWriteMode) hClose $ \file -> do
        hSetEncoding file utf8
        putStrLn ("[open] " ++ path)
        pure (FileHandle path file)
    either (raise . AcquireFileError . displayException) pure outcome

-- requests 在开启前驱动 FileResource 打开文件；开启期间 Context 保存真实 Handle，后续 require 复用它。
instance OpenSessionLayer m => OpenSessionHandler m where
  openSession = rawoutput []

instance CloseSessionLayer m => CloseSessionHandler m where
  closeSession = do
    FileHandle path file <- require @FileHandle
    outcome <- liftIO (tryIOError (hClose file))
    either (raise . CloseSessionError . displayException) pure outcome
    liftIO (putStrLn ("[close] " ++ path))
    rawoutput []

-- 读取是原子句柄：只执行 IO，把读到的文本交出；FileText 由挂在它下面的 ExtractFileText 解析。
-- Input FileSession 已在它之前开启（同份已开启的 scope 不再执行 open）。
instance ReadFileContentLayer m => ReadFileContentHandler m where
  readFileContent = do
    FileHandle _ file <- require @FileHandle
    outcome <- liftIO $ tryIOError $ do
      hSeek file AbsoluteSeek 0
      -- 读完仍保留当前 Handle，供同一链随后写入；不使用会关闭它的 hGetContents。
      fix (\next characters -> do
        finished <- hIsEOF file
        if finished
          then pure (reverse characters)
          else hGetChar file >>= \character -> next (character : characters)) []
    contents <- either (raise . ReadFileContentError . displayException) pure outcome
    rawoutput [contents]

-- parser 挂在读取句柄下：rawinput 是句柄本次交出的 list（一段文本），解析成文件状态（和类型）。
-- alternative 的选择读取驱动它：rawinput 执行读取句柄，读一次文件。
instance ParseFileTextLayer m => ParseFileTextHandler m where
  parseFileText = do
    contents <- rawinput
    text <- case contents of
      [whole] -> pure whole
      _ -> raise (ParseFileTextError "File read returned no text")
    pure (if null text then Blank else Written text)

instance DetectFileSessionLayer m => DetectFileSessionHandler m where
  detectFileSession = do
    FileHandle _ file <- require @FileHandle
    outcome <- liftIO (tryIOError (hIsClosed file))
    closed <- either (raise . DetectFileSessionError . displayException) pure outcome
    -- handles 已按 handler 粗定位；detect 只做值级细化：文件已关闭才归此处。
    unless closed $
      raise (DetectFileSessionError "File handle is still open; failure not located in FileSession")

-- TODO：Error 的处置是另一条驱动链，设计确定前 resolve 不做任何事；不调用 close，也不重放读写。
instance ResolveFileSessionLayer m => ResolveFileSessionHandler m where
  resolveFileSession = pure ()

-- 两个候选都是完整的写入链：Input FileSession 先开启文件，分支契约决定由哪个候选执行。
-- 选择在 AST 的 alternative 中自动完成，候选本身不判断条件；链退出后自动关闭文件。
instance WriteFirstLineLayer m => WriteFirstLineHandler m where
  writeFirstLine = do
    FileHandle path file <- require @FileHandle
    let line = "file-demo: the file was empty; this is the first line.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn "[read] (empty file)"
      hSeek file SeekFromEnd 0
      hPutStr file line
      hFlush file
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . WriteFirstLineError . displayException) pure outcome
    rawoutput []

instance AppendLineLayer m => AppendLineHandler m where
  appendLine = do
    contents <- require @String
    FileHandle path file <- require @FileHandle
    -- 明确消费读出的文本；只追加，不截断已有内容。
    let line = "file-demo: read " ++ show (length contents) ++ " characters before this append.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn ("[read] " ++ contents)
      hSeek file SeekFromEnd 0
      hPutStr file line
      hFlush file
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . AppendLineError . displayException) pure outcome
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "b01d99cca0f1ce9183a891f133f9e576"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance SDK.Root (Wrap effect) value

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.LocateFileError (Wrap effect) where
  raise (Effects.LocateFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.LocateFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ValidateFileNameError (Wrap effect) where
  raise (Effects.ValidateFileNameError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ValidateFileNameFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ParseFileNameError (Wrap effect) where
  raise (Effects.ParseFileNameError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ParseFileNameFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.AcquireFileError (Wrap effect) where
  raise (Effects.AcquireFileError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.AcquireFileFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.OpenSessionError (Wrap effect) where
  raise (Effects.OpenSessionError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.OpenSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.CloseSessionError (Wrap effect) where
  raise (Effects.CloseSessionError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.CloseSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.DetectFileSessionError (Wrap effect) where
  raise (Effects.DetectFileSessionError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.DetectFileSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ResolveFileSessionError (Wrap effect) where
  raise (Effects.ResolveFileSessionError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ResolveFileSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ReadFileContentError (Wrap effect) where
  raise (Effects.ReadFileContentError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ReadFileContentFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.ParseFileTextError (Wrap effect) where
  raise (Effects.ParseFileTextError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.ParseFileTextFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.WriteFirstLineError (Wrap effect) where
  raise (Effects.WriteFirstLineError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.WriteFirstLineFailure description)

instance FrameworkTypes.KnownSymbol effect => SDK.Raises Effects.AppendLineError (Wrap effect) where
  raise (Effects.AppendLineError description) = Wrap (SDK.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) Effects.AppendLineFailure description)

instance SDK.Reads [Char] (Wrap "FileResource") where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "FileSession") where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads FileHandle (Wrap "FileRecovery") where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads FileHandle (Wrap "ReadFile") where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads () (Wrap "WriteFirstLine") where
  require = Wrap (SDK.projectContext "ExtractFileText" "FileTextBlank" Effects.ContextBindingError (\(Effects.FileText value) -> case value of { Blank -> Just (); _ -> Nothing }) (readFileText))

instance SDK.Reads FileHandle (Wrap "WriteFirstLine") where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads String (Wrap "AppendLine") where
  require = Wrap (SDK.projectContext "ExtractFileText" "FileTextWritten" Effects.ContextBindingError (\(Effects.FileText value) -> case value of { Written field -> Just field; _ -> Nothing }) (readFileText))

instance SDK.Reads FileHandle (Wrap "AppendLine") where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Raw (Wrap "ValidateFileName") where
  rawinput = Wrap runLocateFile

instance SDK.Raw (Wrap "FileLocation") where
  rawinput = Wrap runValidateFileName

instance SDK.Raw (Wrap "ExtractFileText") where
  rawinput = Wrap runReadFile

instance SDK.RawOutputs (Wrap effect)

runLocateFile :: Effects.App [String]
runLocateFile =
  SDK.handleFailure
  . SDK.atomicHandle "runLocateFile" [("FileLocation", () <$ getFileName)] []
  . SDK.enterHandler "LocateFile" $
    runWrap @"LocateFile" (SDK.super "locateFile" Effects.locateFile)

runValidateFileName :: Effects.App [String]
runValidateFileName =
  SDK.handleFailure $
    runWrap @"ValidateFileName" (SDK.super "validateFileName" Effects.validateFileName)

getFileName :: Effects.App Effects.FileName
getFileName =
  SDK.handleFailure
  . SDK.callContext "FileLocation"
      (\value bindings -> bindings { Effects.boundFileLocation = Just value }) $
    Effects.FileName <$> runWrap @"FileLocation" (SDK.super "parseFileName" Effects.parseFileName)

readFileName :: Effects.App Effects.FileName
readFileName =
  SDK.handleFailure $
    SDK.readContext "FileLocation" Effects.ContextBindingError Effects.boundFileLocation

getOpenedFile :: Effects.App Effects.OpenedFile
getOpenedFile =
  SDK.handleFailure
  . SDK.callContext "FileResource"
      (\value bindings -> bindings { Effects.boundFileResource = Just value }) $
    getFileName >> Effects.OpenedFile <$> runWrap @"FileResource" (SDK.super "acquireFile" Effects.acquireFile)

readOpenedFile :: Effects.App Effects.OpenedFile
readOpenedFile =
  SDK.handleFailure $
    SDK.readContext "FileResource" Effects.ContextBindingError Effects.boundFileResource

openFileSession :: Effects.App [String]
openFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "openFileSession" [] []
  . SDK.openScope "FileSession" Effects.ScopeBindingError (Just (() <$ closeFileSession))
  . SDK.enterHandler "FileSession" $
    getOpenedFile >> runWrap @"FileSession" (SDK.super "openSession" Effects.openSession)

closeFileSession :: Effects.App [String]
closeFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "closeFileSession" [] []
  . SDK.closeScope "FileSession" Effects.ScopeBindingError
  . SDK.enterHandler "FileSession" $
    runWrap @"FileSession" (SDK.superClose "closeSession" Effects.closeSession)

detectFileRecovery :: Effects.App ()
detectFileRecovery =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "FileRecovery" $
    runWrap @"FileRecovery" (SDK.super "detectFileSession" Effects.detectFileSession)

resolveFileRecovery :: Effects.App ()
resolveFileRecovery =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "FileRecovery" $
    runWrap @"FileRecovery" (SDK.super "resolveFileSession" Effects.resolveFileSession)

runReadFile :: Effects.App [String]
runReadFile =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runReadFile" [("ExtractFileText", () <$ getFileText)] []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "ReadFile" $
    openFileSession >> runWrap @"ReadFile" (SDK.super "readFileContent" Effects.readFileContent)

getFileText :: Effects.App Effects.FileText
getFileText =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.callContext "ExtractFileText"
      (\value bindings -> bindings { Effects.boundExtractFileText = Just value }) $
    Effects.FileText <$> runWrap @"ExtractFileText" (SDK.super "parseFileText" Effects.parseFileText)

readFileText :: Effects.App Effects.FileText
readFileText =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure $
    SDK.readContext "ExtractFileText" Effects.ContextBindingError Effects.boundExtractFileText

runWriteFirstLine :: Effects.App [String]
runWriteFirstLine =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runWriteFirstLine" [] []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "WriteFirstLine" $
    openFileSession >> runWrap @"WriteFirstLine" (SDK.super "writeFirstLine" Effects.writeFirstLine)

runAppendLine :: Effects.App [String]
runAppendLine =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runAppendLine" [] []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "AppendLine" $
    openFileSession >> runWrap @"AppendLine" (SDK.super "appendLine" Effects.appendLine)

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [SDK.ScopeHandler Effects.ContextValues Effects.Errors]
newScopeHandlers = sequence
  [ SDK.newScopeHandler "FileSession" ["FileLocation"] (Just "FileResource")
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, SDK.ErrorHandler Effects.Errors Effects.App)]
errorHandlers =
  [ (Just "FileSession", SDK.ErrorHandler "FileRecovery"
      (\failure -> case (SDK.origin failure, SDK.detail failure) of
        (_, Effects.ReadFileContentFailure) -> True
        (_, Effects.WriteFirstLineFailure) -> True
        (_, Effects.AppendLineFailure) -> True
        _ -> False)
      (Just detectFileRecovery) (Just resolveFileRecovery))
  ]
