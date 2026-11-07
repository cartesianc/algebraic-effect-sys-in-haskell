# 原子 handler 复用：facade 原型

**状态：设计原型，SDK 未实现。** 生成器目前不认识下面的目标写法。这里手写了 gen 应该产出的结果，用来验证目标写法能否运行；请不要把它当成当前可用接口。

例子：报表和回复用同一套打开、写入、读取、解析和打印操作，只是资产和前驱不同。

## 目标写法

### 1. Types.hs：只写数据结构

```haskell
data TextFile = TextFile FilePath Handle deriving Show
newtype Body = Body String deriving Show
newtype LineCount = LineCount Int deriving Show
newtype Level = Level Int deriving Show
data FileState = Blank | Filled Body deriving Show
```

### 2. Effects.hs：effect 是业务配置

```haskell
effects =
  [ -- 两份资产，同一个获取和开关 handler
    EffectSpec { name = "ReportFile"
               , typing = Context { asset = Asset @TextFile "OpenedReport", request = Just "acquireFile", require = Just (), stream = Nothing }
               , input = "Root", demands = [requires "ReportPath"] }
  , EffectSpec { name = "ReplyFile"
               , typing = Context { asset = Asset @TextFile "OpenedReply", request = Just "acquireFile", require = Just (), stream = Nothing }
               , input = "Root", demands = [requires "ReplyPath"] }
  , EffectSpec { name = "ReportScope"
               , typing = Scoped { open = Just "openTextFile", close = Just "closeTextFile" }
               , input = "Root", demands = [requests "OpenedReport", requires "OpenedReport"] }
  , EffectSpec { name = "ReplyScope"
               , typing = Scoped { open = Just "openTextFile", close = Just "closeTextFile" }
               , input = "Root", demands = [requests "OpenedReply", requires "OpenedReply"] }

    -- 同一个 writeText：Input 和 demand 都不同
  , EffectSpec { name = "WriteReport"
               , typing = Excu { handler = Just "writeText" }
               , input = "ReportScope", demands = [requires "OpenedReport", requires "ReportBody"] }
  , EffectSpec { name = "WriteReply"
               , typing = Excu { handler = Just "writeText" }
               , input = "ReplyScope", demands = [requires "OpenedReply", requires "ReplyBody"] }

    -- 同一个 readText：前驱不同
  , EffectSpec { name = "MarkReply", typing = Excu { handler = Just "markRead" }, input = "Root", demands = [] }
  , EffectSpec { name = "ReadReport"
               , typing = Excu { handler = Just "readText" }
               , input = "Root", demands = [requires "ReportPath"] }
  , EffectSpec { name = "ReadReply"
               , typing = Excu { handler = Just "readText" }
               , input = "MarkReply", demands = [requires "ReplyPath"] }

    -- 同一个解析器，挂在不同的句柄下
  , EffectSpec { name = "ReportCounter"
               , typing = Context { asset = Asset @LineCount "ReportStats", request = Just "countLines", require = Just (), stream = Nothing }
               , input = "ReadReport", demands = [] }
  , EffectSpec { name = "ReplyCounter"
               , typing = Context { asset = Asset @LineCount "ReplyStats", request = Just "countLines", require = Just (), stream = Nothing }
               , input = "ReadReply", demands = [] }

    -- 同一个 Stream 解析器和消费者
  , EffectSpec { name = "FeedA", typing = Stream { handler = Just "nextA" }, input = "Root", demands = [] }
  , EffectSpec { name = "ParserA"
               , typing = Context { asset = Asset @Level "LevelA", request = Just "parseLevel", require = Just (), stream = Nothing }
               , input = "FeedA", demands = [] }
  , EffectSpec { name = "ShowA", typing = Excu { handler = Just "showLevel" }, input = "Root", demands = [streams "LevelA"] }
    -- 其余注册写法相同，完整列表见下方“文件说明”中的 Effects.hs
  ]
```

### 3. Handlers.hs：handler 是类方法

没有参数，不出现上游、scope、细化资产和 effect 错误。这部分是可编译的真实代码，见 [Facade.hs](Facade.hs)。

```haskell
instance OpenTextFileInputs m => OpenTextFileHandler m where
  openTextFile = do
    TextFile path _ <- request @TextFile
    liftIO (putStrLn ("[open] " ++ path))
    pure Nothing

instance WriteTextInputs m => WriteTextHandler m where
  writeText = do
    TextFile path file <- require @TextFile
    Body text <- require @Body
    liftIO (hPutStr file text >> hFlush file >> putStrLn ("[write] " ++ path))
    pure Nothing

instance CountLinesInputs m => CountLinesHandler m where
  countLines = do
    output <- upstreamOutput
    contents <- maybe (failWith "no text") pure output
    pure (LineCount (length (lines contents)))

instance ShowLevelInputs m => ShowLevelHandler m where
  showLevel = do
    samples <- require @(History Level)
    case latest samples of
      Just (Level value) -> liftIO (putStrLn ("[level] " ++ show value))
      Nothing -> pure ()
    when (historySize samples >= 3) (failWith "enough deliveries")
    pure Nothing
```

### 4. AST.hs：不变

```haskell
ast = chained
  [ parallel [node "WriteReport", node "WriteReply"]
  , parallel [node "ReadReport", node "ReadReply"]
  , chained [node "ShowReport", node "ShowReply"]
  , alternative [node "OnBlank", node "OnFilled"]
  , lifelong [node "ShowA", node "ShowB"]
  ]
```

### 5. gen 的产出（这里是手写的）

每个 handler 一个类，上下文来自它读取的表示类型，不含 Input 链，见 [Contracts.hs](Contracts.hs)：

```haskell
type WriteTextInputs m = (Reads TextFile m, Reads Body m, MonadIO m)
class WriteTextHandler m where writeText :: m (Maybe String)
```

每个 effect 一个入口，前驱和细化资产的包装写在 handler 外面：

```haskell
writeReport    = openReport >> writeText
writeReply     = openReply >> writeText
readReply      = markReply >> readText
getReportStats = ReportStats <$> countLines
```

路由由 demands 推出，键是表示类型加当前调用者：

```haskell
instance Provides TextFile App where
  require = route "TextFile"
    [ ("WriteReport", require @OpenedReport >>= \(OpenedReport value) -> pure value)
    , ("WriteReply", require @OpenedReply >>= \(OpenedReply value) -> pure value)
    , ... ]
```

## 实测结果

与现有显式写法（[Handlers.hs](Handlers.hs)）对比，日期 2026-11-07：

- `parallel` 的交错和两个 lifelong 单元的交错除外，其余输出行相同。
- 写入的文件内容正确；每个 scope 各开关一次。
- `alternative` 按资产状态选择候选；Stream 解析器和 lifelong 消费者按各自资产工作。
- lifelong 结束时报 `origin = "ShowA"`，共享 handler 的失败归到具体 effect。
- handler 调用 `openTextFile` 或读取 `@OpenedReport`，GHC 都直接拒绝。

## 模拟了什么，没有覆盖什么

- `Contracts.hs`、`Generated/Handlers.hs` 里的入口与路由是手写的。原型（`Generated/Program.hs`）由现有写法生成，并未从目标注册推导。
- 重新运行生成器会覆盖手写的 `Generated/Handlers.hs`。
- 位置和正文 Context、Stream 方法体各不相同，没有共享，仍是现有写法。
- 不在此范围：重复开关资源的方法（`checkReopen` 等）、`requests` 刷新规则、手动 close、绑定配错时的生成期检查。

## 还没定的写法

下面几项只是为了让原型跑起来，不是已确认的接口：

- Context 用 `request = Just "handler名"` 引用 handler。
- `failWith` 代替按 effect 生成的错误构造器。
- `upstreamOutput`、`upstreamRaw` 读取挂接上游的本次输出。
- 每个 handler 一个类，类名和 `Inputs` 别名按 handler 名生成。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| [Facade.hs](Facade.hs) | 目标写法的手写 handler |
| [Contracts.hs](Contracts.hs) | 手写的目标生成契约 |
| [Handlers.hs](Handlers.hs)、[Effects.hs](Effects.hs) | 同一程序的现有写法；生成器用它们产出原型，也是对比基线 |
| [Generated/Handlers.hs](Generated/Handlers.hs) | 手写绑定与路由之后的生成副本 |

## 运行

在仓库根目录执行，不进入 Cabal 构建：

```bash
cabal exec -- ghc -threaded -isdk -idemo -main-is FacadeProbe.Main -outputdir dist-newstyle/facade -o dist-newstyle/facade/facade-probe demo/FacadeProbe/Main.hs
```

```bash
dist-newstyle/facade/facade-probe
```

程序最后以 `Failed ... "enough deliveries"` 结束，这是 lifelong 的临时失败规则，属预期结果。
