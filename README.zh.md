# nimctx - Nim Context MCP Server

[![CI](https://github.com/nim-community/nimctx/actions/workflows/ci.yml/badge.svg)](https://github.com/nim-community/nimctx/actions/workflows/ci.yml)
[![Nim Version](https://img.shields.io/badge/nim-%3E%3D2.2.0-orange.svg)](https://nim-lang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) | 中文

Nim Context MCP Server 为 AI 编程助手提供深度的 Nim 项目和标准库上下文，包括依赖包的模块索引。

本项目 nimctx 解决了 AI 编程助手缺乏关于 Nim 项目的深度上下文的问题。

## 问题

当 AI 助手（如 Claude）帮助进行 Nim 编程时，它们面临以下几个挑战：

1. **无法轻松访问标准库文档** - 无法查找标准库函数、它们的签名或文档
2. **依赖包盲点** - 不知道项目依赖哪些包或这些包中有什么可用内容
3. **导入困惑** - 无法判断 `import json` 是指标准库还是第三方包
4. **版本兼容性** - 难以检查代码是否能在不同 Nim 版本下正常工作
5. **手动上下文** - 用户必须手动复制粘贴文档或包信息到对话中

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
│       ├── version_compat.nim  # Nim 版本兼容性检查
│       ├── stdlib/
│       │   └── indexer.nim     # 标准库索引
│       ├── packages/
│       │   └── indexer.nim     # 依赖包索引
│       ├── project/
│       │   └── manager.nim     # nimble依赖管理
│       └── utils/
│           ├── cache.nim       # 内存缓存系统
│           ├── logging.nim     # 日志工具
│           ├── indexing.nim    # 索引工具和通用类型
│           └── sqlite_indexer.nim  # SQLite 符号索引后端
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

- **SQLite 索引后端**: 使用 SQLite 后端进行持久化、高效的符号存储，实现快速查找
- **多级缓存**: 文件索引缓存 + 内存搜索缓存，实现最佳性能
- **增量索引**: 按需索引依赖包，自动发现新包
- **版本兼容性检查**: 通过 choosenim 集成，测试代码在多个 Nim 版本下的兼容性
- **智能识别**: 自动区分 stdlib 和包模块

## 许可证

MIT
