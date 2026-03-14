# Common indexing utilities for stdlib and package indexing

import std/[os, strutils, times, osproc, json, options]

type
  SymbolEntry* = object
    name*: string
    kind*: string
    code*: string
    description*: string
    line*: int
    col*: int

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

proc parseJsonDoc*(jsonPath: string): seq[SymbolEntry] =
  ## Parse a JSON doc file and extract symbol entries
  ## Returns a sequence of SymbolEntry objects
  if not fileExists(jsonPath):
    return @[]
  
  try:
    let content = readFile(jsonPath)
    let json = parseJson(content)
    
    if json.hasKey("entries") and json["entries"].kind == JArray:
      for entry in json["entries"]:
        var sym = SymbolEntry()
        
        if entry.hasKey("name"):
          sym.name = entry["name"].getStr()
        if entry.hasKey("type"):
          sym.kind = entry["type"].getStr()
        if entry.hasKey("code"):
          sym.code = entry["code"].getStr()
        if entry.hasKey("description"):
          sym.description = entry["description"].getStr()
        if entry.hasKey("line"):
          sym.line = entry["line"].getInt()
        if entry.hasKey("col"):
          sym.col = entry["col"].getInt()
        
        result.add(sym)
  except:
    stderr.writeLine("Error parsing JSON doc: " & getCurrentExceptionMsg())
    return @[]

proc getJsonDocPath*(modulePath: string): string =
  ## Get the path to the JSON doc file for a module
  let moduleDir = modulePath.parentDir()
  let moduleName = extractFilename(modulePath).replace(".nim", "")
  return moduleDir / "htmldocs" / moduleName & ".json"
