# Common indexing utilities for stdlib and package indexing

import std/[os, strutils, times, osproc]

proc indexSingleModule*(nimPath, modulePath: string): bool {.gcsafe, raises: [].} =
  ## Generate JSON doc for a single module using `nim jsondoc`
  ## This procedure is designed to run in worker threads (taskpools)
  ## Returns true if JSON doc was generated successfully or cache is fresh
  try:
    if not fileExists(modulePath):
      return false
    
    let moduleDir = modulePath.parentDir()
    let moduleName = extractFilename(modulePath).replace(".nim", "")
    let jsonPath = moduleDir / "htmldocs" / moduleName & ".json"
    
    # Check if cached version is fresh
    if fileExists(jsonPath):
      let cacheTime = getFileInfo(jsonPath).lastWriteTime
      let moduleTime = getFileInfo(modulePath).lastWriteTime
      if cacheTime > moduleTime:
        return true  # Cache is fresh
    
    # Generate jsondoc
    let cmd = nimPath & " jsondoc " & quoteShell(modulePath)
    let (_, exitCode) = execCmdEx(cmd)
    
    return exitCode == 0 and fileExists(jsonPath)
  except:
    return false
