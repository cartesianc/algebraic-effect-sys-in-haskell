-- `effect-codegen ast` 的输出与 Generated/Workflow.json 的内容：业务树的原样结构及其源码位置、规范形式、
-- Hanging 挂载、结构诊断，以及这些结论所依据的源码文件指纹，编码为 JSON。
-- 结构事实都来自 Gen.Workflow 与 Language.AST 的规范化；这里只组织字段。
module Framework.Gen.Emit.Workflow (renderWorkflowReport) where

import Data.Char (ord)
import Data.List (intercalate)
import Framework.Gen.Workflow (SourceRange(..), SourceSite(..), hangingMarks, prepareWorkflow)
import Framework.Language.AST (WorkflowF(..), normalizeWorkflow, workflowOrigins)
import Framework.Recursion (Fix(..))
import Numeric (showHex)

-- rows 是 Hanging 各行求值得到的 hook 与目标数，targets 是前端从源码给出的目标名与源码位置。
-- sources 是已加载的 AST、Workflow、Hanging 文件与其 MD5（十六进制，CRLF 先换成 LF）；不存在的 Hanging 为 null。
-- 读取方重新计算这些文件的 MD5，全部一致时这份结果仍对应当前源码，无需再运行 SDK。
renderWorkflowReport :: String -> Fix WorkflowF -> [([String], Int)] -> [[(String, [[Int]])]] -> [SourceSite]
                     -> [(FilePath, Maybe String)] -> String
renderWorkflowReport namespace tree rows targets sites sources = encode $ JObject
  [ ("schemaVersion", JNumber 1)
  , ("namespace", JText namespace)
  , ("sources", JArray [JObject [("file", JText file), ("md5", maybe JNull JText digest)] | (file, digest) <- sources])
  , ("source", source [] tree)
  , ("workflow", normal [] normalized)
  , ("hanging", JArray [mount hooks row | ((hooks, _), row) <- zip rows targets])
  , ("diagnostics", JArray (map JText (mounting ++ structural)))
  ]
  where
    (normalized, relocate) = normalizeWorkflow tree
    origins = workflowOrigins tree
    (mounting, marks) = either (\problem -> ([problem], [])) (\found -> ([], found)) (hangingMarks rows targets)
    structural = either (pure . show) (const []) (prepareWorkflow tree marks)
    -- 原样结构：路径与 Hanging 的源码位置一致；能从源码读出的位置附具名绑定与范围。
    source path (Fix layer) = JObject ([("path", path' path), ("kind", JText (kind layer))] ++ effect layer
      ++ site path ++ [("children", JArray [source at child | (at, child) <- indexed path (childrenOf layer)])])
    site path = case [found | found <- sites, sitePath found == path] of
      found : _ -> [ ("names", JArray (map JText (siteNames found)))
                   , ("range", maybe JNull range (siteRange found))
                   , ("readable", JBool (siteReadable found)) ]
      [] -> []
    -- 规范形式：路径即 NodeId；sourcePaths 列出化简进这个节点的原样路径。
    normal path (Fix layer) = JObject ([("path", path' path), ("kind", JText (kind layer))] ++ effect layer
      ++ [ ("sourcePaths", JArray [path' from | (from, to) <- origins, to == path])
         , ("children", JArray [normal at child | (at, child) <- indexed path (childrenOf layer)]) ])
    mount hooks row = JObject
      [ ("hooks", JArray (map JText hooks))
      , ("targets", JArray [JObject [ ("name", JText name)
          , ("sourcePaths", JArray (map path' paths))
          , ("paths", JArray (map path' (concatMap relocate paths))) ] | (name, paths) <- row]) ]
    range (SourceRange file startLine startColumn endLine endColumn) = JObject
      [ ("file", JText file)
      , ("start", JArray [JNumber startLine, JNumber startColumn])
      , ("end", JArray [JNumber endLine, JNumber endColumn]) ]
    path' = JArray . map JNumber
    effect (Node selected) = [("effect", JText selected)]
    effect _ = []
    kind layer = case layer of
      Node _ -> "node"
      Chain _ -> "chain"
      Parallel _ -> "parallel"
      Alternative _ -> "alternative"
      Lifelong _ -> "lifelong"
    childrenOf layer = case layer of
      Node _ -> []
      Chain children -> children
      Parallel children -> children
      Alternative children -> children
      Lifelong children -> children
    indexed path children = [(path ++ [index], child) | (index, child) <- zip [0 ..] children]

data Json = JNull | JBool Bool | JNumber Int | JText String | JArray [Json] | JObject [(String, Json)]

-- 带缩进输出，生成区里的文件因此可以按行比较。只含标量与标量数组的小结构（路径、范围）写在一行。
-- 非 ASCII 字符按 UTF-8 原样输出；控制字符与孤立代理用四位十六进制转义。
encode :: Json -> String
encode = render 0
  where
    render depth value = case value of
      JNull -> "null"
      JBool flag -> if flag then "true" else "false"
      JNumber number -> show number
      JText text -> quote text
      JArray items
        | all flat items -> "[" ++ intercalate ", " (map (render depth) items) ++ "]"
        | otherwise -> "[\n" ++ intercalate ",\n" [pad (depth + 1) ++ render (depth + 1) item | item <- items]
            ++ "\n" ++ pad depth ++ "]"
      JObject fields
        | all (flat . snd) fields -> "{" ++ intercalate ", " [quote key ++ ": " ++ render depth item | (key, item) <- fields] ++ "}"
        | otherwise -> "{\n" ++ intercalate ",\n" [pad (depth + 1) ++ quote key ++ ": " ++ render (depth + 1) item | (key, item) <- fields]
            ++ "\n" ++ pad depth ++ "}"
    flat item = case item of
      JArray items -> all flat items
      JObject _ -> False
      _ -> True
    pad depth = replicate (2 * depth) ' '
    quote text = "\"" ++ concatMap escape text ++ "\""
    escape '"' = "\\\""
    escape '\\' = "\\\\"
    escape c | ord c < 32 || (ord c >= 0xd800 && ord c <= 0xdfff) =
      let hex = showHex (ord c) "" in "\\u" ++ replicate (4 - length hex) '0' ++ hex
    escape c = [c]
