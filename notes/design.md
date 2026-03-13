# nimctx - Nim 上下文服务设计方案

## 一、项目定位

**nimctx** 是一个专为 Nim 语言设计的 MCP (Model Context Protocol) 服务器，为 AI 编程助手提供深度的 Nim 项目和标准库上下文。

### 与现有项目的关系
- **nimcp**: SDK/库，用于构建 MCP 服务器 → **nimctx 依赖它**
- **nimgenie**: 通用编程助手（半成品） → **nimctx 更聚焦、更完善**

## 二、核心功能

### 2.1 标准库文档服务

#### Resources
| URI 模式 | 说明 |
|---------|------|
| `nim://stdlib/{module}` | 标准库模块完整文档 |
| `nim://stdlib/{module}/{proc}` | 特定过程/类型文档 |
| `nim://stdlib/index` | 标准库模块索引 |

#### Tools
| 工具名 | 参数 | 返回值 |
|-------|------|-------|
| `search_stdlib` | query, module?, type? | 匹配符号列表 |
| `get_proc_signature` | module, proc_name | 签名、文档、示例 |

### 2.2 项目依赖分析服务

#### Resources
| URI 模式 | 说明 |
|---------|------|
| `nim://project/info` | 当前项目基本信息 |
| `nim://project/deps` | 项目依赖列表 |
| `nim://project/dep-tree` | 依赖树可视化 |
| `nim://pkg/{pkgname}/info` | 特定包详情 |
| `nim://pkg/{pkgname}/exports` | 包的导出符号 |

#### Tools
| 工具名 | 参数 | 返回值 |
|-------|------|-------|
| `list_dependencies` | direct_only?, format? | 依赖列表 |
| `search_in_deps` | query, dep_pattern? | 符号及所属包 |
| `get_module_docs` | module_path | 模块文档 |
| `resolve_import` | import_path | 模块来源、路径 |

### 2.3 代码分析辅助

#### Tools
| 工具名 | 参数 | 返回值 |
|-------|------|-------|
| `analyze_nim_code` | code, context? | 语法检查、符号解析 |
| `suggest_fix` | error_message, code | 修复建议 |

## 三、架构设计

```
┌─────────────────────────────────────────────────────────┐
│                     nimctx                               │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ MCP Protocol│  │ Nim Project │  │ Package Discovery│  │
│  │  (nimcp)    │  │  Analyzer   │  │     Module       │  │
│  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘  │
│         │                │                   │           │
│         └────────────────┼───────────────────┘           │
│                          ▼                               │
│              ┌─────────────────────┐                    │
│              │    Context Provider │                    │
│              └─────────────────────┘                    │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
                ┌─────────────────────┐
                │   MCP Clients       │
                │ (Claude, RooCode...)│
                └─────────────────────┘
```

## 四、数据流

### 4.1 标准库查询
```
用户提问 → search_stdlib(query) → 查索引 → 返回匹配符号
```

### 4.2 依赖查询
```
用户提问 → list_dependencies() → nimble dump/deps → 解析缓存 → 返回列表
```

### 4.3 包文档查询
```
用户提问 → get_module_docs(path) → nimble path → 解析 .nim 文件 → 提取文档
```

## 五、缓存策略

| 数据类型 | 存储方式 | 失效条件 |
|---------|---------|---------|
| Stdlib 索引 | 文件 (~/.cache/nimctx/stdlib.idx) | Nim 版本变化 |
| 包元数据 | 内存 + 文件 | 包版本变化 |
| 模块文档 | LRU 内存 | 进程重启 |
| nimble dump | 内存 | 5min 或 nimble 文件变化 |

## 六、配置

```json
// nimctx.json
{
  "transport": "stdio",
  "nim": {
    "nimPath": "/usr/local/bin/nim",
    "nimblePath": "/usr/local/bin/nimble",
    "stdlibPath": "/usr/local/lib/nim/lib"
  },
  "indexing": {
    "enableStdlibIndex": true,
    "enableDepIndex": true,
    "cacheDir": "~/.cache/nimctx"
  },
  "limits": {
    "maxSearchResults": 20,
    "maxDocLength": 10000
  }
}
```

## 七、实现路线图

| 阶段 | 内容 | 时间 |
|-----|------|------|
| Phase 1 | 基础 MCP 框架 + stdlib 服务 | 1-2 周 |
| Phase 2 | nimble 依赖发现 + 包元数据 | 1-2 周 |
| Phase 3 | 模块文档提取 + 符号搜索 | 2 周 |
| Phase 4 | 代码分析辅助 | 2-3 周 |
| Phase 5 | 优化 + 文档 | 1-2 周 |

## 八、部署

### 安装
```bash
nimble install nimctx
```

### MCP Client 配置
```json
{
  "mcpServers": {
    "nim": {
      "command": "nimctx",
      "args": ["--transport", "stdio"]
    }
  }
}
```

## 九、命名对比

| 候选名 | 含义 | 评价 |
|-------|------|------|
| **nimctx** | Nim + Context | ✅ 简洁、明确、与 nimcp 区分明显 |
| nimsage | Nim + Sage | 强调智能，但不够直接 |
| nimat | Nim + mate | 简短，但语义不明确 |
| nimray | Nim + X-ray | 强调分析，但不够通用 |
| nimbrell | Nim + Umbrella | 强调覆盖，但过长 |

**最终选择: nimctx**
