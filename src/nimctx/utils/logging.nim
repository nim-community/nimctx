# Logging utilities

import std/[times, strutils]

type
  LogLevel* = enum
    llDebug, llInfo, llWarn, llError

var currentLevel* = llInfo

proc log*(level: LogLevel, msg: string) =
  ## Log a message
  if level < currentLevel:
    return
  
  let timestamp = now().format("yyyy-MM-dd HH:mm:ss")
  let levelStr = case level
    of llDebug: "DEBUG"
    of llInfo: "INFO"
    of llWarn: "WARN"
    of llError: "ERROR"
  
  stderr.writeLine("[" & timestamp & "] [" & levelStr & "] " & msg)

proc debug*(msg: string) = log(llDebug, msg)
proc info*(msg: string) = log(llInfo, msg)
proc warn*(msg: string) = log(llWarn, msg)
proc error*(msg: string) = log(llError, msg)
