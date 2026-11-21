-- 自动生成的编译副本；请修改上级 Handlers.hs 后重新生成。
{-# LANGUAGE AllowAmbiguousTypes #-}
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

module FileDemo.Generated.Handlers (handlerSourceFingerprint, runLocateFile, runValidateFileName, getFileName, readFileName, getOpenedFile, readOpenedFile, openFileSession, closeFileSession, detectFileRecovery, resolveFileRecovery, runReadFile, getFileBlank, readFileBlank, getFileWritten, readFileWritten, runWriteFirstLine, runAppendLine, newScopeHandlers, errorHandlers) where

import qualified Framework.Generated as SDK
import qualified FileDemo.Generated.Effects as Effects
import qualified Control.Monad.IO.Class as FrameworkIO
import qualified Data.Proxy as FrameworkProxy
import qualified GHC.TypeLits as FrameworkTypes
import Framework.SDK (Raises(..), Raw(..), Reads(..), rawoutput)
import FileDemo.Generated.Effects
import FileDemo.Types
import Control.Exception (displayException)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import System.FilePath ((</>))
import System.IO (readFile')
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

-- 文件名由 requests 驱动，生产时已经过 ValidateFileName 的检查。取得资源时确保文件存在，资产只记路径。
instance AcquireFileLayer m => AcquireFileHandler m where
  acquireFile = do
    path <- require @String
    outcome <- liftIO $ tryIOError $ do
      appendFile path ""
      putStrLn ("[open] " ++ path)
    either (raise . AcquireFileError . displayException) pure outcome
    pure (FileHandle path)

-- requests 在开启前驱动 FileResource 取得文件；开启期间各 handler 按同一路径读写。
instance OpenSessionLayer m => OpenSessionHandler m where
  openSession = rawoutput []

instance CloseSessionLayer m => CloseSessionHandler m where
  closeSession = do
    FileHandle path <- require @FileHandle
    liftIO (putStrLn ("[close] " ++ path))
    rawoutput []

-- 读取是原子句柄：只执行 IO，把读到的文本交出；挂在它下面的 BlankText、FilledText 各自解析。
-- Input FileSession 已在它之前开启（同份已开启的 scope 不再执行 open）。
instance ReadFileContentLayer m => ReadFileContentHandler m where
  readFileContent = do
    FileHandle path <- require @FileHandle
    -- 严格读取：读完即关闭文件，同一链随后的写入再按路径打开。
    outcome <- liftIO (tryIOError (readFile' path))
    contents <- either (raise . ReadFileContentError . displayException) pure outcome
    rawoutput [contents]

-- 两个 parser 挂在读取句柄下：rawinput 是句柄本次交出的 list（一段文本）。
-- 不符合自己的情形就 raise：在 alternative 的选择中只算放弃，另一个候选的 parser 接着判定。
instance ParseBlankTextLayer m => ParseBlankTextHandler m where
  parseBlankText = do
    contents <- rawinput
    case contents of
      [""] -> pure (EmptyText "")
      _ -> raise (ParseBlankTextError "the file is not empty")

instance ParseWrittenTextLayer m => ParseWrittenTextHandler m where
  parseWrittenText = do
    contents <- rawinput
    case contents of
      [whole] | not (null whole) -> pure (WrittenText whole)
      _ -> raise (ParseWrittenTextError "the file is empty")

instance DetectFileSessionLayer m => DetectFileSessionHandler m where
  detectFileSession = do
    FileHandle path <- require @FileHandle
    outcome <- liftIO (tryIOError (readFile' path))
    -- handles 已按 handler 粗定位；detect 只做值级细化：文件已无法读取才归此处。
    unless (either (const True) (const False) outcome) $
      raise (DetectFileSessionError "File is still readable; failure not located in FileSession")

-- TODO：Error 的处置是另一条驱动链，设计确定前 resolve 不做任何事；不调用 close，也不重放读写。
instance ResolveFileSessionLayer m => ResolveFileSessionHandler m where
  resolveFileSession = pure ()

-- 两个候选都是完整的写入链：Input FileSession 先开启文件，ReadFile 输出的判定决定由哪个候选执行。
-- 选择在 AST 的 alternative 中自动完成，候选本身不判断条件；链退出后自动关闭文件。
instance WriteFirstLineLayer m => WriteFirstLineHandler m where
  writeFirstLine = do
    FileHandle path <- require @FileHandle
    let line = "file-demo: the file was empty; this is the first line.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn "[read] (empty file)"
      appendFile path line
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . WriteFirstLineError . displayException) pure outcome
    rawoutput []

instance AppendLineLayer m => AppendLineHandler m where
  appendLine = do
    WrittenText contents <- require @WrittenText
    FileHandle path <- require @FileHandle
    -- 明确消费读出的文本；只追加，不截断已有内容。
    let line = "file-demo: read " ++ show (length contents) ++ " characters before this append.\n"
    outcome <- liftIO $ tryIOError $ do
      putStrLn ("[read] " ++ contents)
      appendFile path line
      putStrLn ("[write] " ++ path ++ ": " ++ line)
    either (raise . AppendLineError . displayException) pure outcome
    rawoutput []

-- 记录本编译副本实际使用的手写源码；启动前检查，避免执行过期方法体。
handlerSourceFingerprint :: Maybe String
handlerSourceFingerprint = Just "dfaf82ce66ae2ef135c435eaded1a621"

-- 以下由 gen 生成。每个 effect 一个类型标签：handler 在标签下执行，
-- 读取、rawinput 与错误按标签在编译期解析到这个 effect 的来源，不改写 handler 方法体。
newtype Wrap (effect :: FrameworkTypes.Symbol) (method :: FrameworkTypes.Symbol) value = Wrap { runWrap :: Effects.App value }
  deriving (Functor, Applicative, Monad, FrameworkIO.MonadIO)

-- 类型标签上的名字：effect 名与方法名只写在标签上，需要字符串时从这里取。
nameOf :: forall name. FrameworkTypes.KnownSymbol name => String
nameOf = FrameworkTypes.symbolVal (FrameworkProxy.Proxy @name)

-- 在标签下执行 handler，交给 Root 的 superhandler；方法名取自标签。close 的调用点用 callClose。
call :: forall effect method value. (FrameworkTypes.KnownSymbol method)
  => Wrap effect method value -> Effects.App value
call handler = runWrap (SDK.super (nameOf @method) handler)

callClose :: forall effect method value. (FrameworkTypes.KnownSymbol method)
  => Wrap effect method value -> Effects.App value
callClose handler = runWrap (SDK.superClose (nameOf @method) handler)

instance SDK.Root (Wrap effect method) value

instance (SDK.HandlerError problem Effects.Errors, FrameworkTypes.KnownSymbol effect)
    => SDK.Raises problem (Wrap effect method) where
  raise problem = Wrap (SDK.failEffect (nameOf @effect) failure description)
    where (failure, description) = SDK.raised problem

instance SDK.Reads [Char] (Wrap "FileResource" method) where
  require = Wrap (SDK.coerce <$> readFileName)

instance SDK.Reads FileHandle (Wrap "FileSession" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads FileHandle (Wrap "FileRecovery" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads FileHandle (Wrap "ReadFile" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads EmptyText (Wrap "WriteFirstLine" method) where
  require = Wrap (SDK.coerce <$> readFileBlank)

instance SDK.Reads FileHandle (Wrap "WriteFirstLine" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Reads WrittenText (Wrap "AppendLine" method) where
  require = Wrap (SDK.coerce <$> readFileWritten)

instance SDK.Reads FileHandle (Wrap "AppendLine" method) where
  require = Wrap (SDK.coerce <$> readOpenedFile)

instance SDK.Raw (Wrap "ValidateFileName" "validateFileName") where
  rawinput = Wrap runLocateFile

instance SDK.Raw (Wrap "FileLocation" "parseFileName") where
  rawinput = Wrap runValidateFileName

instance SDK.Raw (Wrap "BlankText" "parseBlankText") where
  rawinput = Wrap runReadFile

instance SDK.Raw (Wrap "FilledText" "parseWrittenText") where
  rawinput = Wrap runReadFile

instance SDK.RawOutputs (Wrap effect method)

runLocateFile :: Effects.App [String]
runLocateFile =
  SDK.handleFailure
  . SDK.atomicHandle "runLocateFile" []
  . SDK.enterHandler "LocateFile" $
    call @"LocateFile" @"locateFile" Effects.locateFile

runValidateFileName :: Effects.App [String]
runValidateFileName =
  SDK.handleFailure $
    call @"ValidateFileName" @"validateFileName" Effects.validateFileName

getFileName :: Effects.App Effects.FileName
getFileName =
  SDK.handleFailure
  . SDK.callContext "FileLocation"
      (\value bindings -> bindings { Effects.boundFileLocation = Just value }) $
    Effects.FileName <$> call @"FileLocation" @"parseFileName" Effects.parseFileName

readFileName :: Effects.App Effects.FileName
readFileName =
  SDK.handleFailure $
    SDK.readContext "FileLocation" Effects.ContextBindingError Effects.boundFileLocation

getOpenedFile :: Effects.App Effects.OpenedFile
getOpenedFile =
  SDK.handleFailure
  . SDK.callContext "FileResource"
      (\value bindings -> bindings { Effects.boundFileResource = Just value }) $
    getFileName >> Effects.OpenedFile <$> call @"FileResource" @"acquireFile" Effects.acquireFile

readOpenedFile :: Effects.App Effects.OpenedFile
readOpenedFile =
  SDK.handleFailure $
    SDK.readContext "FileResource" Effects.ContextBindingError Effects.boundFileResource

openFileSession :: Effects.App [String]
openFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "openFileSession" []
  . SDK.openScope "FileSession" Effects.ScopeBindingError (Just (() <$ closeFileSession))
  . SDK.enterHandler "FileSession" $
    getOpenedFile >> call @"FileSession" @"openSession" Effects.openSession

closeFileSession :: Effects.App [String]
closeFileSession =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicScope "closeFileSession" []
  . SDK.closeScope "FileSession" Effects.ScopeBindingError
  . SDK.enterHandler "FileSession" $
    callClose @"FileSession" @"closeSession" Effects.closeSession

detectFileRecovery :: Effects.App ()
detectFileRecovery =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "FileRecovery" $
    call @"FileRecovery" @"detectFileSession" Effects.detectFileSession

resolveFileRecovery :: Effects.App ()
resolveFileRecovery =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "FileRecovery" $
    call @"FileRecovery" @"resolveFileSession" Effects.resolveFileSession

runReadFile :: Effects.App [String]
runReadFile =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runReadFile" []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "ReadFile" $
    openFileSession >> call @"ReadFile" @"readFileContent" Effects.readFileContent

getFileBlank :: Effects.App Effects.FileBlank
getFileBlank =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.callContext "BlankText"
      (\value bindings -> bindings { Effects.boundBlankText = Just value }) $
    Effects.FileBlank <$> call @"BlankText" @"parseBlankText" Effects.parseBlankText

readFileBlank :: Effects.App Effects.FileBlank
readFileBlank =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure $
    SDK.readContext "BlankText" Effects.ContextBindingError Effects.boundBlankText

getFileWritten :: Effects.App Effects.FileWritten
getFileWritten =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.callContext "FilledText"
      (\value bindings -> bindings { Effects.boundFilledText = Just value }) $
    Effects.FileWritten <$> call @"FilledText" @"parseWrittenText" Effects.parseWrittenText

readFileWritten :: Effects.App Effects.FileWritten
readFileWritten =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure $
    SDK.readContext "FilledText" Effects.ContextBindingError Effects.boundFilledText

runWriteFirstLine :: Effects.App [String]
runWriteFirstLine =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runWriteFirstLine" []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "WriteFirstLine" $
    openFileSession >> call @"WriteFirstLine" @"writeFirstLine" Effects.writeFirstLine

runAppendLine :: Effects.App [String]
runAppendLine =
  SDK.withErrorPath ["FileSession"]
  . SDK.handleFailure
  . SDK.atomicHandle "runAppendLine" []
  . SDK.withScopeDependencies ["FileSession"]
  . SDK.enterHandler "AppendLine" $
    openFileSession >> call @"AppendLine" @"appendLine" Effects.appendLine

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
