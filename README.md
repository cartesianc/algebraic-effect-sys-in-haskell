# myframework

以可读 Effect IR、Haskell EDSL 和递归 AST 为基础的声明式函数式架构。

注册 effect 时绑定 impl，类型类方法提供句柄，AST 组织模块控制流，interpreter 统一执行。模块后端面向监听、mock、stress 和 log/show。

```haskell
main = interpreter ast effect
```

## 文档

- [简版：有什么功能，怎么用](docs/design/QUICKSTART.md)
- [完整设计：目录与文件关系](docs/design/README.md)
- [现有源码、运行命令与实现进度](docs/design/IMPLEMENTATION.md)

最新设计统一放在 `docs/design/`。文中的 API 是目标写法；当前源码仍是早期试验实现。

现有 core 与发布证据的维护说明见 [trustbase/README.md](trustbase/README.md)。
