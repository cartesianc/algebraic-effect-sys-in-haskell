-- handler 是不带参数的类方法；SDK 按注册装配上游、会话与读取来源，运行编译 Generated 副本。
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Werror=missing-methods #-}

module LinesDemo.Handlers () where

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
