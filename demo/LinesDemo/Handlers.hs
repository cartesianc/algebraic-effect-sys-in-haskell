-- handler 是不带参数的类方法；SDK 按注册装配上游、会话与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module LinesDemo.Handlers () where

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
