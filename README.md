# nimctx - Nim Context MCP Server

[![CI](https://github.com/nim-community/nimctx/actions/workflows/ci.yml/badge.svg)](https://github.com/nim-community/nimctx/actions/workflows/ci.yml)
[![Nim Version](https://img.shields.io/badge/nim-%3E%3D2.2.0-orange.svg)](https://nim-lang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

English | [中文](README.zh.md)

Nim Context MCP Server provides deep context for Nim projects and standard library for AI programming assistants, including module indexing for dependency packages.

This project nimctx solves the problem of AI programming assistants lacking deep cont
  ext about Nim projects.

  The Problem

  When AI assistants (like Claude) help with Nim programming, they face several challen
  ges:

  1. No easy access to stdlib docs - Can't look up standard library functions, their si
     tures, or documentation
  2. Dependency blind spot - Don't know what packages a project depends on or what's av
     able in them
  3. Import confusion - Can't tell if import json refers to stdlib or a third-party pac
     e
  4. Version compatibility - Hard to check if code works across different Nim versions
  5. Manual context - Users have to manually copy-paste docs or package info into conve
     tions


## Features

### Standard Library Support
- **Standard Library Documentation Query**: Search and retrieve symbols, procedure signatures, and documentation from the Nim standard library
- **Module Documentation**: Get exported symbols and documentation from stdlib modules

### Dependency Package Support
- **Dependency Listing**: Get project dependency information via nimble
- **Package Module Indexing**: Index modules from installed packages (e.g., `jsony`, `chronos`, etc.)
- **Cross-Package Search**: Search symbols across multiple dependency packages
- **Package-Specific Search**: Search symbols within a specific package

### Development Assistance
- **Import Resolution**: Resolve the source of import statements (stdlib or dependency packages)
- **Procedure Signatures**: Get detailed signatures for procedures from stdlib or dependency packages
- **Smart Caching**: Search result caching for improved response speed
- **Project Root Support**: All tools support `projectRoot` parameter to analyze any Nim project

## Installation

### Build from Source

```bash
git clone <repository>
cd nimctx
nimble build
```

Or using nim command:

```bash
nim c -d:release src/nimctx.nim
```

## Usage

### Command Line

```bash
./nimctx
```

The server communicates with MCP clients via standard input/output (stdio).

### MCP Client Configuration

#### Claude Desktop (macOS)

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

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

Add to VS Code settings:

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

## Available Tools

| Tool Name | Description | Parameters |
|-----------|-------------|------------|
| `search_stdlib` | Search for functions, types, variables in Nim STANDARD LIBRARY ONLY. Use ONLY when user explicitly asks about: 'stdlib', 'standard library', or mentions specific stdlib modules like 'strutils', 'json', 'os', 'system', etc. | `query`, `moduleFilter?`, `symbolType?`, `packageFilter?` |
| `get_proc_signature` | Get detailed function signature from INDEXED packages only. Use ONLY when: 1) User mentions a specific function name AND 2) User explicitly mentions a stdlib module (strutils, json, etc.) or an already-indexed package. | `procName`, `packageName?`, `projectRoot?` |
| `list_dependencies` | List project dependencies from nimble. Use ONLY when user explicitly asks about project dependencies, nimble packages, or 'what packages does this project use'. | `directOnly?`, `projectRoot?` |
| `get_module_docs` | Get documentation for a module from INDEXED packages only. Use ONLY when user explicitly asks about a specific module by name (e.g., 'strutils', 'json', 'system') and wants to see its documentation. | `modulePath`, `packageName?`, `projectRoot?` |
| `resolve_import` | Find where an imported module comes from (stdlib path, nimble package location, or local file). Use when user asks: 'Where is X imported from?', 'Which package provides Y?', 'Find source of import Z'. | `importPath`, `projectRoot?` |
| `check_version_compat` | Check Nim version compatibility by testing code against different Nim versions | `filePath?`, `testAllInstalled?`, `updateNimble?`, `projectRoot?` |
| `list_nim_versions` | List all available Nim versions | - |

### Usage Examples

**Search Standard Library:**
```
search_stdlib(query: "split", moduleFilter: "strutils")
```

**Search in Dependency Packages:**
```
search_stdlib(query: "parseJson", packageFilter: "jsony")
```

**Get Procedure Signature from Package:**
```
get_proc_signature(procName: "fromJson", packageName: "jsony")
```

**List Dependencies:**
```
list_dependencies(directOnly: true)
```

**Specify Project Root:**
```
# Analyze dependencies of a specific project
list_dependencies(projectRoot: "/path/to/my/project")

# Search symbols in another project
search_stdlib(query: "parseJson", projectRoot: "/path/to/my/project")
```

**Check Version Compatibility:**
```
check_version_compat(filePath: "src/myfile.nim", testAllInstalled: true)
```

**List Nim Versions:**
```
list_nim_versions()
```

## Configuration

```json
// ~/.config/nimctx/config.json or ./nimctx.json
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

## Project Structure

```
nimctx/
├── src/
│   ├── nimctx.nim              # Main entry + MCP server
│   └── nimctx/
│       ├── config.nim          # Configuration management
│       ├── stdlib/
│       │   └── indexer.nim     # Standard library indexing
│       ├── packages/
│       │   └── indexer.nim     # Dependency package indexing
│       ├── project/
│       │   └── manager.nim     # Nimble dependency management
│       └── utils/
│           ├── cache.nim       # In-memory cache system
│           └── logging.nim     # Logging utilities
├── tests/                      # Tests
├── examples/                   # Configuration examples
└── notes/                      # Design documents
```

## Technical Features

- **Multi-Level Caching**: File index cache + in-memory search cache
- **Incremental Indexing**: Index dependency packages on demand
- **Concurrency Safe**: Uses ref types and closures for concurrent handling
- **Smart Recognition**: Automatically distinguishes between stdlib and package modules

## License

MIT
