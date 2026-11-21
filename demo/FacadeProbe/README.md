# 原子 handler 复用：FacadeProbe

**状态：已由 SDK 实现（Stage 2，2026-11-08）。** 本目录的注册与 handler 就是当前写法，Generated 由 `effect-codegen` 生成，不再手写。

例子：报表和回复用同一套打开、写入、读取、解析和打印 handler，只是资产和前驱不同；两个持续数据源共用同一个 parser 和消费者。

## 代码长什么样

### 1. Types.hs：只写数据结构

资产都由 `String` 构造（[固定形式](../../docs/ASSETS.md#fixed-form)）：文件资源只记路径，行数与读数保存十进制文本。

```haskell
newtype TextFile = TextFile String deriving (Eq, Show)
newtype Body = Body String deriving (Eq, Show)
newtype LineCount = LineCount String deriving (Eq, Show)
newtype Level = Level String deriving (Eq, Show)
newtype EmptyReport = EmptyReport String deriving (Eq, Show)
```

### 2. Effects.hs：effect 是业务配置

注册里的字段写 handler 名；同一个 handler 绑定多次，Input 与 demands 各不相同（节选，完整列表见 [Effects.hs](Effects.hs)，局部辅助 `context`、`scoped`、`excu` 等写在 `effects` 的 `where` 里）：

```haskell
effects =
  [ -- 两份资产，同一个获取 handler；两个 Scoped 注册共用开关 handler，彼此独立。
    -- 取得文件前先驱动路径；后面的读取只读这次发布的路径。
    context "ReportFile" (Asset @TextFile "OpenedReport") "acquireFile" "Root" [requests "ReportPath", requires "ReportPath"]
  , context "ReplyFile" (Asset @TextFile "OpenedReply") "acquireFile" "Root" [requests "ReplyPath", requires "ReplyPath"]
  , scoped "ReportScope" "OpenedReport"     -- open = "openTextFile", close = "closeTextFile"
  , scoped "ReplyScope" "OpenedReply"
    -- 同一个 writeText：Input 和 demands 都不同
  , excu "WriteReport" "writeText" "ReportScope" [requests "ReportBody", requires "OpenedReport", requires "ReportBody"]
  , excu "WriteReply" "writeText" "ReplyScope" [requests "ReplyBody", requires "OpenedReply", requires "ReplyBody"]
    -- 同一个 readText：前驱不同
  , excu "MarkReply" "markRead" "Root" []
  , excu "ReadReport" "readText" "Root" [requires "ReportPath"]
  , excu "ReadReply" "readText" "MarkReply" [requires "ReplyPath"]
    -- 同一个 parser，挂在不同的句柄下；只在被 requests 时执行
  , context "ReportCounter" (Asset @LineCount "ReportStats") "countLines" "ReadReport" []
  , context "ReplyCounter" (Asset @LineCount "ReplyStats") "countLines" "ReadReply" []
    -- 打印 requests 行数：gen 把读取链展开为它的前驱
  , excu "ShowReport" "showCount" "Root" [requests "ReportStats", requires "ReportStats"]
  , excu "ShowReply" "showCount" "Root" [requests "ReplyStats", requires "ReplyStats"]
    -- 同一个 Stream parser 和消费者
  , stream "FeedA" "nextA"                  -- Input 为 Root 的 Stream
  , continuous "ParserA" (Asset @Level "LevelA") "parseLevel" "FeedA"
  , excu "ShowA" "showLevel" "Root" [streams "LevelA"]
  ...
  ]
```

### 3. Handlers.hs：handler 是类方法

没有参数，不出现上游、scope、细化资产或 effect 错误（节选自 [Handlers.hs](Handlers.hs)）：

```haskell
instance OpenTextFileLayer m => OpenTextFileHandler m where
  openTextFile = do
    TextFile path <- require @TextFile
    liftIO (putStrLn ("[open] " ++ path))
    rawoutput []

instance WriteTextLayer m => WriteTextHandler m where
  writeText = do
    TextFile path <- require @TextFile
    Body text <- require @Body
    liftIO (appendFile path text >> putStrLn ("[write] " ++ path))
    rawoutput []

instance CountLinesLayer m => CountLinesHandler m where
  countLines = do
    output <- rawinput
    contents <- case output of
      [text] -> pure text
      _ -> raise (CountLinesError "no text")
    pure (LineCount (show (length (lines contents))))

instance ShowLevelLayer m => ShowLevelHandler m where
  showLevel = do
    Level value <- require @Level
    seen <- stream @Level
    let number = length seen
    liftIO (putStrLn ("[level] " ++ value ++ " at delivery " ++ show number))
    when (number >= 3) (raise (ShowLevelError "enough deliveries"))
    rawoutput []
```

交付编号是 `stream @Level` 读到的 x:xs 的长度：本次交付加上同一会话中更早的交付（[持续资产按 x:xs 读取](../../docs/STREAM_LIFELONG.md#flow)）。两个来源共用 parser 和消费 handler，各自的会话分别计数。

### 4. AST.hs

读取不单独挂载：ShowReport、ShowReply 经 requests 在自己的入口里先读取、解析，再打印。

```haskell
ast = chain
  [ parallel [node "WriteReport", node "WriteReply"]
  , chain [node "ShowReport", node "ShowReply"]
  , alternative [node "OnBlank", node "OnFilled"]
  , lifelong [node "ShowA", node "ShowB"]
  ]
```

### 5. gen 的产出

每个 handler 一个类和一份 Layer，内容由它的各个绑定推出（[Generated/Effects.hs](Generated/Effects.hs)）：

```haskell
type WriteTextLayer m = (SDK.Reads Body m, SDK.Reads TextFile m, SDK.RawOutputs m, SDK.Raises WriteTextError m, MonadIO m)
class WriteTextHandler m where
  writeText :: m [String]
```

每个 effect 一个类型标签和一个入口，前驱与驱动写在 handler 外面；读取按“表示类型 + effect”路由到细化资产（[Generated/Handlers.hs](Generated/Handlers.hs)）：

```haskell
runWriteReport = ⟨入口包装⟩ $
  getReportBody >> openReportScope >> runWrap @"WriteReport" (FrameworkRuntime.super "writeText" FrameworkGenerated.writeText)
runReadReply = ⟨入口包装⟩ $
  runMarkReply >> runWrap @"ReadReply" (FrameworkRuntime.super "readText" FrameworkGenerated.readText)

instance FrameworkRuntime.Reads (TextFile) (Wrap "WriteReport") where
  require = Wrap ((\(FrameworkGenerated.OpenedReport value) -> value) <$> readOpenedReport)

instance FrameworkRuntime.Raw (Wrap "ReportCounter") where
  rawinput = Wrap (runReadReport)
```

## 实测结果

2026-11-08，与 2026-11-07 的手写原型（当时的 Contracts.hs、Facade.hs 与手改的 Generated/Handlers.hs）运行结果对比：

- 除 `parallel` 的交错和两个 lifelong 单元的交错外，输出行相同；写入的 `report.txt`、`reply.txt` 内容相同；每个 scope 各开关一次。
- `alternative` 按资产状态选择候选（`[state] filled, 42 characters`）；2026-11-21 起改为按 `InspectReport` 输出下哪个 Context 解析成功选择（[U5](../../docs/NEXT_STAGES.md#urgent-race)），资产改为固定形式（[U4](../../docs/NEXT_STAGES.md#urgent-assets)），输出不变；Stream parser 和 lifelong 消费者按各自资产工作。
- lifelong 结束时报 `origin = "ShowA"`；`detail` 由原型的 `ShowAFailure` 变为 `ShowLevelFailure`：失败属于 handler，发生在哪个 effect 记在 `origin`。
- 原型实测时 GHC 放过的“handler 调用另一个 handler 的类方法”，现在由 gencode 报错；读取未声明的表示类型、在非挂接 handler 中使用 `rawinput`，同样在生成期报错。以上报错路径本次没有逐一触发。

## 运行

在仓库根目录执行，不进入 Cabal 构建：

```bash
cabal run effect-codegen -- workflow FacadeProbe
```

```bash
cabal exec -- ghc -threaded -isdk -idemo -main-is FacadeProbe.Main -outputdir dist-newstyle/facade -o dist-newstyle/facade/facade-probe demo/FacadeProbe/Main.hs
```

```bash
dist-newstyle/facade/facade-probe
```

程序最后以 `Failed ... "enough deliveries"` 结束，这是 lifelong 的临时失败规则，属预期结果。
