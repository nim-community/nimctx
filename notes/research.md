# Nim MCP 调研笔记

## 一、现有 Nim MCP 生态

### 1.1 NimCP (gokr)
- **类型**: MCP SDK 库
- **特点**: 
  - 基于宏的 API
  - 支持 notifications
  - 支持 stdio 和 SSE 传输
- **用途**: 构建 MCP 服务器的基础库
- **GitHub**: https://github.com/gokr/nimcp

### 1.2 Nimgenie (gokr)
- **类型**: 通用 MCP 服务器（半成品）
- **功能**:
  - 源代码索引
  - Nimble 依赖管理
  - 构建管理
  - 测试运行
  - 数据库访问
- **GitHub**: https://github.com/gokr/nimgenie

### 1.3 Mummyx (gokr)
- **类型**: HTTP 服务器库
- **特点**:
  - Mummy 的分支
  - 支持 SSE
  - 基于 taskpool 的并发
  - 支持大文件上传

## 二、Nimble 关键命令

### 2.1 包信息获取
```bash
# 输出包元数据（JSON 格式）
nimble dump --json

# 示例输出:
{
  "name": "project",
  "version": "0.1.0",
  "author": "author",
  "requires": [
    {"name": "nim", "str": ">= 2.2.0", ...}
  ],
  "bin": ["project"],
  "srcDir": "src"
}
```

### 2.2 依赖树获取
```bash
# 输出依赖树（JSON 格式）
nimble deps --format:json

# 示例输出:
[
  {
    "name": "nim",
    "version": ">= 2.2.0",
    "resolvedTo": "2.2.0",
    "dependencies": []
  }
]
```

### 2.3 包路径查询
```bash
# 获取已安装包的路径
nimble path <pkgname>

# 示例:
nimble path chronos
# 输出: /Users/xxx/.nimble/pkgs2/chronos-4.0.4-xxx
```

### 2.4 包存储结构
```
~/.nimble/pkgs2/
├── 包名-版本-校验和/
│   ├── 包名.nimble
│   └── 源代码...
```

## 三、Nim 标准库概览

### 3.1 Core 模块
- system（自动导入）
- macros（AST API）
- typetraits（编译时反射）
- algorithm（通用算法）

### 3.2 数据结构
- tables（哈希表）
- sets（集合）
- sequtils（序列操作）
- lists（链表）
- deques（双端队列）

### 3.3 字符串处理
- strutils（常用操作）
- strformat（字符串插值）
- strscans（scanf 宏）
- parseutils（解析辅助）
- unicode（UTF-8 支持）

### 3.4 文件与 OS
- os（操作系统接口）
- osproc（进程通信）
- paths（路径处理）
- streams（流接口）
- dirs（目录操作）
- files（文件操作）

### 3.5 网络与异步
- asyncdispatch（异步调度）
- asyncnet（异步套接字）
- httpclient（HTTP 客户端）
- asynchttpserver（HTTP 服务器）
- net（高级套接字 API）
- uri（URI 处理）

### 3.6 解析器
- json（JSON 解析）
- parsejson（底层 JSON 解析）
- parsexml（XML 解析）
- parsecfg（配置解析）
- parsecsv（CSV 解析）
- parsesql（SQL 解析）
- pegs（PEG 文法）

### 3.7 其他重要模块
- times（时间处理）
- random（随机数）
- math（数学运算）
- hashes（哈希计算）
- base64（Base64 编解码）
- json（JSON 处理）
- unittest（单元测试）

## 四、相关工具库

### 4.1 pkginfo
- **作者**: openpeep
- **功能**: 编译时收集 .nimble 元数据和依赖信息
- **GitHub**: https://github.com/openpeep/pkginfo
- **特点**:
  ```nim
  import pkginfo
  when pkg("jsony").getVersion > v"0.1.1":
    echo "using newer jsony"
  ```

## 五、Nimble 内部 API

### 5.1 关键模块位置
```
~/.nimble/pkgs2/nimble-0.22.1-xxx/nimblepkg/
├── packageparser.nim    # 包信息解析
├── version.nim          # 版本解析和比较
├── deps.nim            # 依赖处理
├── download.nim        # 包下载
├── paths.nim           # 路径处理
└── options.nim         # 配置选项
```

### 5.2 可用的解析函数
- `getPkgInfo(dir, options, nimBin)` - 从目录获取包信息
- `parseRequires(req)` - 解析 requires 字符串
- `getInstalledPkgs(nimBin, libsDir, options)` - 获取已安装包列表
