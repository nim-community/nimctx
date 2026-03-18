# Logging utilities using chronicles
#
# Usage:
#   import nimctx/utils/logging
#   logging.initLogging()
#   info "Message", key = value
#
# To enable file logging at compile time:
#   -d:chronicles_sinks="file(/path/to/nimctx.log)"

import chronicles
export chronicles  # Re-export all chronicles symbols

import std/[os, syncio]

when defined(posix):
  import std/posix

const defaultLogPath* = when defined(macosx) or defined(linux):
    getHomeDir() / ".local" / "share" / "nimctx" / "nimctx.log"
  else:
    getHomeDir() / "nimctx" / "nimctx.log"

var logFile*: File = nil
  ## Global log file handle (nil means using default chronicles output)

proc initLogging*() =
  ## Initialize logging to the default log file at runtime (POSIX only)
  ## Log file location:
  ##   - Linux/macOS: ~/.local/share/nimctx/nimctx.log
  ##   - Windows: ~/nimctx/nimctx.log
  ## 
  ## For cross-platform file logging, use compile-time flag instead:
  ##   -d:chronicles_sinks="file(path)"
  
  let logDir = parentDir(defaultLogPath)
  if not dirExists(logDir):
    createDir(logDir)
  
  if logFile != nil and logFile != stdout and logFile != stderr:
    logFile.close()
  
  logFile = open(defaultLogPath, fmAppend)
  
  when defined(posix):
    # Redirect stdout and stderr to log file
    let logFd = getFileHandle(logFile)
    let err = dup2(logFd, getFileHandle(stderr))
    if err != -1:
      discard dup2(logFd, getFileHandle(stdout))
