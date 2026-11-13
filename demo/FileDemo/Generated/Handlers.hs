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
-- handler 是不带参数的类方法：按表示类型 require 资产，用 raise 报告自己的失败。
-- 上游、scope 和资产名都不出现在这里；gen 按注册装配，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module FileDemo.Generated.Handlers (handlerSourceFingerprint, runLocateFile, runValidateFileName, getFileName, readFileName, getOpenedFile, readOpenedFile, openFileSession, closeFileSession, detectFileRecovery, resolveFileRecovery, runReadFile, getFileText, readFileText, runWriteFirstLine, runAppendLine, newScopeHandlers, scopeCleanups, errorHandlers, contextInjections) where

import qualified Framework.Generated as FrameworkRuntime
import qualified FileDemo.Generated.Effects as FrameworkGenerated
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import FileDemo.Types
import Framework.SDK (Raises(..), Raw(..), Reads(..))
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
  locateFile = pure ["demo" </> "FileDemo" </> "output.txt"]

-- Pure：raw 是上层交出的路径 list；逐项检查后原样交给下面的 parser。没有 IO，也不读资产。
instance ValidateFileNameLayer m => ValidateFileNameHandler m where
  validateFileName = do
    paths <- raw
    unless (all (\path -> not (null path) && '\0' `notElem` path) paths) $
      raise (ValidateFileNameError "File name must be nonempty and contain no NUL character")
    pure paths

-- Context 是细化 parser：通过检查的 list 恰好有一个路径时，才是文件名资产。
instance ParseFileNameLayer m => ParseFileNameHandler m where
  parseFileName = do
    paths <- raw
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
  openSession = pure []

instance CloseSessionLayer m => CloseSessionHandler m where
  closeSession = do
    FileHandle path file <- require @FileHandle
    outcome <- liftIO (tryIOError (hClose file))
    either (raise . CloseSessionError . displayException) pure outcome
    liftIO (putStrLn ("[close] " ++ path))
    pure []

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
    pure [contents]

-- parser 挂在读取句柄下：raw 是句柄本次交出的 list（一段文本），解析成文件状态（和类型）。
-- alternative 的选择读取驱动它：raw 执行读取句柄，读一次文件。
instance ParseFileTextLayer m => ParseFileTextHandler m where
  parseFileText = do
    contents <- raw
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
    pure []

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
    pure []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "28e83d56924ecdd4406b15ae341a9d46"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、raw 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype At (effect :: FrameworkTypes.Symbol) value = At { runAt :: FrameworkGenerated.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.LocateFileError (At effect) where
  raise (FrameworkGenerated.LocateFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.LocateFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ValidateFileNameError (At effect) where
  raise (FrameworkGenerated.ValidateFileNameError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ValidateFileNameFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ParseFileNameError (At effect) where
  raise (FrameworkGenerated.ParseFileNameError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ParseFileNameFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AcquireFileError (At effect) where
  raise (FrameworkGenerated.AcquireFileError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AcquireFileFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.OpenSessionError (At effect) where
  raise (FrameworkGenerated.OpenSessionError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.OpenSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.CloseSessionError (At effect) where
  raise (FrameworkGenerated.CloseSessionError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.CloseSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.DetectFileSessionError (At effect) where
  raise (FrameworkGenerated.DetectFileSessionError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.DetectFileSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ResolveFileSessionError (At effect) where
  raise (FrameworkGenerated.ResolveFileSessionError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ResolveFileSessionFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ReadFileContentError (At effect) where
  raise (FrameworkGenerated.ReadFileContentError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ReadFileContentFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.ParseFileTextError (At effect) where
  raise (FrameworkGenerated.ParseFileTextError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.ParseFileTextFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.WriteFirstLineError (At effect) where
  raise (FrameworkGenerated.WriteFirstLineError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.WriteFirstLineFailure description)

instance FrameworkTypes.KnownSymbol effect => FrameworkRuntime.Raises FrameworkGenerated.AppendLineError (At effect) where
  raise (FrameworkGenerated.AppendLineError description) = At (FrameworkRuntime.failEffect
    (FrameworkTypes.symbolVal (FrameworkProxy.Proxy :: FrameworkProxy.Proxy effect)) FrameworkGenerated.AppendLineFailure description)

instance FrameworkRuntime.Reads ([Char]) (At "FileResource") where
  require = At ((\(FrameworkGenerated.FileName value) -> value) <$> readFileName)

instance FrameworkRuntime.Reads (FileHandle) (At "FileSession") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads (FileHandle) (At "FileRecovery") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads (FileHandle) (At "ReadFile") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads (()) (At "WriteFirstLine") where
  require = At (FrameworkRuntime.projectContext "ExtractFileText" "FileTextBlank" FrameworkGenerated.ContextBindingError (\(FrameworkGenerated.FileText value) -> case value of { Blank -> Just (); _ -> Nothing }) (readFileText))

instance FrameworkRuntime.Reads (FileHandle) (At "WriteFirstLine") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Reads (String) (At "AppendLine") where
  require = At (FrameworkRuntime.projectContext "ExtractFileText" "FileTextWritten" FrameworkGenerated.ContextBindingError (\(FrameworkGenerated.FileText value) -> case value of { Written field -> Just field; _ -> Nothing }) (readFileText))

instance FrameworkRuntime.Reads (FileHandle) (At "AppendLine") where
  require = At ((\(FrameworkGenerated.OpenedFile value) -> value) <$> readOpenedFile)

instance FrameworkRuntime.Raw (At "ValidateFileName") where
  raw = At (runLocateFile)

instance FrameworkRuntime.Raw (At "FileLocation") where
  raw = At (runValidateFileName)

instance FrameworkRuntime.Raw (At "ExtractFileText") where
  raw = At (runReadFile)

runLocateFile :: FrameworkGenerated.App [String]
runLocateFile = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runLocateFile" . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "LocateFile") $
  runAt @"LocateFile" FrameworkGenerated.locateFile

runValidateFileName :: FrameworkGenerated.App [String]
runValidateFileName = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies []) $
  runAt @"ValidateFileName" FrameworkGenerated.validateFileName

getFileName :: FrameworkGenerated.App FrameworkGenerated.FileName
getFileName = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileLocation"
    (\value bindings -> bindings { FrameworkGenerated.boundFileLocation = Just value })) $
  (FrameworkGenerated.FileName <$> runAt @"FileLocation" FrameworkGenerated.parseFileName)

readFileName :: FrameworkGenerated.App FrameworkGenerated.FileName
readFileName = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "FileLocation" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundFileLocation

getOpenedFile :: FrameworkGenerated.App FrameworkGenerated.OpenedFile
getOpenedFile = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.callContext "FileResource"
    (\value bindings -> bindings { FrameworkGenerated.boundFileResource = Just value })) $
  getFileName >> (FrameworkGenerated.OpenedFile <$> runAt @"FileResource" FrameworkGenerated.acquireFile)

readOpenedFile :: FrameworkGenerated.App FrameworkGenerated.OpenedFile
readOpenedFile = (FrameworkRuntime.withErrorPath [] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "FileResource" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundFileResource

openFileSession :: FrameworkGenerated.App [String]
openFileSession = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "openFileSession" . FrameworkRuntime.openScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
  getOpenedFile >> runAt @"FileSession" FrameworkGenerated.openSession

closeFileSession :: FrameworkGenerated.App [String]
closeFileSession = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicScope "closeFileSession" . FrameworkRuntime.closeScope "FileSession" FrameworkGenerated.ScopeBindingError . FrameworkRuntime.withScopeDependencies [] . FrameworkRuntime.enterHandler "FileSession") $
  runAt @"FileSession" FrameworkGenerated.closeSession

detectFileRecovery :: FrameworkGenerated.App ()
detectFileRecovery = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "FileRecovery") $
  runAt @"FileRecovery" FrameworkGenerated.detectFileSession

resolveFileRecovery :: FrameworkGenerated.App ()
resolveFileRecovery = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "FileRecovery") $
  runAt @"FileRecovery" FrameworkGenerated.resolveFileSession

runReadFile :: FrameworkGenerated.App [String]
runReadFile = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runReadFile" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "ReadFile") $
  openFileSession >> runAt @"ReadFile" FrameworkGenerated.readFileContent

getFileText :: FrameworkGenerated.App FrameworkGenerated.FileText
getFileText = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.callContext "ExtractFileText"
    (\value bindings -> bindings { FrameworkGenerated.boundExtractFileText = Just value })) $
  (FrameworkGenerated.FileText <$> runAt @"ExtractFileText" FrameworkGenerated.parseFileText)

readFileText :: FrameworkGenerated.App FrameworkGenerated.FileText
readFileText = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure) $
  FrameworkRuntime.readContext "ExtractFileText" FrameworkGenerated.ContextBindingError FrameworkGenerated.boundExtractFileText

runWriteFirstLine :: FrameworkGenerated.App [String]
runWriteFirstLine = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runWriteFirstLine" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "WriteFirstLine") $
  openFileSession >> runAt @"WriteFirstLine" FrameworkGenerated.writeFirstLine

runAppendLine :: FrameworkGenerated.App [String]
runAppendLine = (FrameworkRuntime.withErrorPath ["FileSession"] . FrameworkRuntime.handleFailure . FrameworkRuntime.atomicHandle "runAppendLine" . FrameworkRuntime.withScopeDependencies ["FileSession"] . FrameworkRuntime.enterHandler "AppendLine") $
  openFileSession >> runAt @"AppendLine" FrameworkGenerated.appendLine

-- SDK 内部：scope 按上游到下游登记，退出时逆序收尾；创建不执行业务方法。
newScopeHandlers :: IO [FrameworkRuntime.ScopeHandler FrameworkGenerated.ContextValues FrameworkGenerated.Errors]
newScopeHandlers = sequence
  [ FrameworkRuntime.newScopeHandler "FileSession" ["FileLocation"] (Just "FileResource")
  ]

-- SDK 自动收尾入口；安装时不关闭资源。
scopeCleanups :: [(String, FrameworkGenerated.App ())]
scopeCleanups =
  [ ("FileSession", () <$ closeFileSession)
  ]

-- Error 回调登记：按 handles 匹配故障的 handler 与协议分类；关联 scope 由 Input 链推导。
errorHandlers :: [(Maybe String, FrameworkRuntime.ErrorHandler FrameworkGenerated.Errors FrameworkGenerated.App)]
errorHandlers =
  [ (Just "FileSession", FrameworkRuntime.ErrorHandler "FileRecovery"
      (\failure -> case (FrameworkRuntime.origin failure, FrameworkRuntime.detail failure) of
        (_, FrameworkGenerated.ReadFileContentFailure) -> True
        (_, FrameworkGenerated.WriteFirstLineFailure) -> True
        (_, FrameworkGenerated.AppendLineFailure) -> True
        _ -> False)
      (Just detectFileRecovery) (Just resolveFileRecovery))
  ]

-- 挂在原子句柄下的 Context：句柄的输出交给它的 parser 解析并发布为资产；没有挂接时输出被丢弃。
contextInjections :: [(String, [(String, FrameworkGenerated.App ())])]
contextInjections =
  [ ("runLocateFile", [("FileLocation", () <$ getFileName)])
  , ("runReadFile", [("ExtractFileText", () <$ getFileText)])
  ]
