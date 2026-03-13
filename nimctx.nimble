# Package

version       = "0.1.0"
author        = "bung87"
description   = "Nim Context MCP Server - Provides Nim stdlib and project dependencies context for AI assistants"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["nimctx"]


# Dependencies

requires "nim >= 1.6.0"
requires "nimcp"
requires "mummy >= 0.4.0"
requires "taskpools >= 0.0.1"
