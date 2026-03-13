# nimctx - Nim Context MCP Server

中文 | [English](README.en.md)

Nim Context MCP Server 为 AI 编程助手提供深度的 Nim 项目和标准库上下文，包括依赖包的模块索引。

## 功能

### 标准库支持
- **标准库文档查询**: 搜索和获取 Nim 标准库的符号、过程签名和文档
- **模块文档**: 获取 stdlib 模块的导出符号和文档

### 依赖包支持
- **依赖包列表**: 通过 nimble 获取项目依赖信息
- **包模块索引**: 索引已安装包的模块（如 `jsony`, `chronos` 等）
- **跨包搜索**: 在多个依赖包中搜索符号
- **包内搜索**: 在特定包中搜索符号

### 开发辅助
- **Import 解析**: 解析 import 语句的来源（stdlib 或依赖包）
- **过程签名**: 获取 stdlib 或依赖包中过程的详细签名
- **智能缓存**: 搜索结果缓存，提升响应速度
- **项目根目录支持**: 所有工具支持 `projectRoot` 参数，可指定任意 Nim 项目进行分析

## 安装

### 从源码构建

```bash
git clone <repository>
cd nimctx
nimble build
```

或使用 nim 命令：

```bash
nim c -d:release src/nimctx.nim
```

## 使用

### 命令行运行

```bash
./nimctx
```

服务器通过标准输入输出 (stdio) 与 MCP 客户端通信。

### MCP Client 配置

#### Claude Desktop (macOS)

编辑 `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "nimctx": {
      "command": "/path/to/nimctx",
      "args": []
    }
  }
}
```

#### RooCode / Cline (VS Code)

在 VS Code 设置中添加：

```json
{
  "mcp.servers": {
    "nimctx": {
      "command": "/path/to/nimctx",
      "args": [],
      "transportType": "stdio",
      "enabled": true
    }
  }
}
```

## 可用工具

| 工具名 | 描述 | 参数 |
|-------|------|------|
| `search_stdlib` | 在 Nim 标准库中搜索函数、类型、变量。仅在用户明确询问 stdlib、standard library 或特定 stdlib 模块（如 strutils、json、os、system 等）时使用 | `query`, `moduleFilter?`, `symbolType?`, `packageFilter?` |
| `get_proc_signature` | 从已索引的包中获取函数的详细签名。仅在用户提到特定函数名且明确提到 stdlib 模块或已索引包时使用 | `procName`, `packageName?`, `projectRoot?` |
| `list_dependencies` | 从 nimble 列出项目依赖。仅在用户明确询问项目依赖、nimble 包或"这个项目使用了什么包"时使用 | `directOnly?`, `projectRoot?` |
| `get_module_docs` | 从已索引的包中获取模块文档。仅在用户明确询问特定模块（如 strutils、json、system）并想要查看其文档时使用 | `modulePath`, `packageName?`, `projectRoot?` |
| `resolve_import` | 查找导入的模块来源（stdlib 路径、nimble 包位置或本地文件）。在用户询问"X 是从哪里导入的？"、"哪个包提供了 Y？"、"查找导入 Z 的来源"时使用 | `importPath`, `projectRoot?` |
| `check_version_compat` | 检查 Nim 版本兼容性，测试代码在不同 Nim 版本下的兼容性 | `filePath?`, `testAllInstalled?`, `updateNimble?`, `projectRoot?` |
| `list_nim_versions` | 列出所有可用的 Nim 版本 | - |

### 使用示例

**搜索标准库:**
```
search_stdlib(query: "split", moduleFilter: "strutils")
```

**在依赖包中搜索:**
```
search_stdlib(query: "parseJson", packageFilter: "jsony")
```

**获取包中过程的签名:**
```
get_proc_signature(procName: "fromJson", packageName: "jsony")
```

**列出依赖:**
```
list_dependencies(directOnly: true)
```

**指定项目根目录:**
```
# 分析特定项目的依赖
list_dependencies(projectRoot: "/path/to/my/project")

# 在其他项目中搜索符号
search_stdlib(query: "parseJson", projectRoot: "/path/to/my/project")
```

**检查版本兼容性:**
```
check_version_compat(filePath: "src/myfile.nim", testAllInstalled: true)
```

**列出 Nim 版本:**
```
list_nim_versions()
```

## 配置

```json
// ~/.config/nimctx/config.json 或 ./nimctx.json
{
  "nim": {
    "nimPath": "/usr/local/bin/nim",
    "nimblePath": "/usr/local/bin/nimble",
    "stdlibPath": "/usr/local/lib/nim/lib"
  },
  "indexing": {
    "enableStdlibIndex": true,
    "cacheDir": "~/.cache/nimctx"
  },
  "limits": {
    "maxSearchResults": 20,
    "maxDocLength": 10000
  }
}
```

## 项目结构

```
nimctx/
├── src/
│   ├── nimctx.nim              # 主入口 + MCP服务器
│   └── nimctx/
│       ├── config.nim          # 配置管理
│       ├── stdlib/
│       │   └── indexer.nim     # 标准库索引
│       ├── packages/
│       │   └── indexer.nim     # 依赖包索引 (新增)
│       ├── project/
│       │   └── manager.nim     # nimble依赖管理
│       └── utils/
│           ├── cache.nim       # 内存缓存系统
│           └── logging.nim     # 日志工具
├── tests/                      # 测试
├── examples/                   # 配置示例
└── notes/                      # 设计文档
```

## 运行测试

```bash
# 运行所有测试
nim c -r tests/test_cache.nim
nim c -r tests/test_packages.nim
nim c -r tests/test_project_manager.nim
nim c -r tests/test_integration.nim
```

## 技术特性

- **多级缓存**: 文件索引缓存 + 内存搜索缓存
- **增量索引**: 按需索引依赖包
- **并发安全**: 使用 ref 类型和闭包处理并发
- **智能识别**: 自动区分 stdlib 和包模块

## 许可证

MIT
