# Standard library indexing using SQLite with FTS support

import std/[os, json, options, cpuinfo, locks]
import taskpools
import ../utils/[sqlite_indexer, indexing]
export indexing.SymbolEntry

export sqlite_indexer

type
  StdlibIndex* = ref object
    sqlite*: SqliteIndex
    stdlibPath*: string
    tp*: TaskPool
    indexLock*: Lock  # Protects concurrent indexing operations
    isIndexed*: bool  # Track if indexing has been done

proc newStdlibIndex*(stdlibPath, cacheDir: string; nimPath: string = ""): StdlibIndex =
  ## Create a new stdlib index with SQLite backend
  var actualNimPath = nimPath
  
  if actualNimPath.len == 0:
    actualNimPath = stdlibPath.parentDir() / "bin" / "nim"
  
  if actualNimPath.len == 0 or not fileExists(actualNimPath):
    actualNimPath = findExe("nim")
  
  if actualNimPath.len == 0 or not fileExists(actualNimPath):
    raise newException(OSError, "nim binary not found for stdlib: " & stdlibPath)
  
  let dbPath = cacheDir / "stdlib.db"
  createDir(cacheDir)
  
  # Create thread pool with number of CPUs
  let numThreads = max(2, cpuinfo.countProcessors())
  
  result = StdlibIndex(
    sqlite: newSqliteIndex(dbPath, actualNimPath),
    stdlibPath: stdlibPath,
    tp: TaskPool.new(numThreads),
    isIndexed: false
  )
  initLock(result.indexLock)

proc findModulePath(index: StdlibIndex, moduleName: string): string =
  ## Find the actual path for a module
  let possiblePaths = [
    index.stdlibPath / "pure" / (moduleName & ".nim"),
    index.stdlibPath / "pure" / "collections" / (moduleName & ".nim"),
    index.stdlibPath / "core" / (moduleName & ".nim"),
    index.stdlibPath / "impure" / (moduleName & ".nim"),
    index.stdlibPath / "std" / (moduleName & ".nim"),
    index.stdlibPath / "std" / "private" / (moduleName & ".nim"),
    index.stdlibPath / (moduleName & ".nim"),
  ]
  
  for path in possiblePaths:
    if fileExists(path):
      return path
  
  return ""

proc scanAndIndexStdlib*(index: StdlibIndex): int =
  ## Scan and index all stdlib modules using parallel processing
  ## Thread-safe: Only one indexing operation at a time
  acquire(index.indexLock)
  defer: release(index.indexLock)
  
  # Check if already indexed
  if index.isIndexed:
    return 0
  
  if not dirExists(index.stdlibPath):
    stderr.writeLine("Warning: Stdlib path not found: " & index.stdlibPath)
    return 0
  
  # Clear existing stdlib data
  index.sqlite.clear()
  
  # Core modules to index (most commonly used)
  let coreModules = [
    "system", "algorithm", "tables", "sets", "sequtils",
    "strutils", "strformat", "strscans", "parseutils", "unicode",
    "json", "osproc", "paths", "times",
    "asyncdispatch", "asyncnet", "httpclient", "net", "uri",
    "streams", "math", "random", "hashes", "base64",
    "re", "typetraits"
  ]
  
  # First pass: collect all module paths
  type ModuleInfo = object
    name: string
    path: string
  var moduleInfos: seq[ModuleInfo] = @[]
  for moduleName in coreModules:
    let modulePath = index.findModulePath(moduleName)
    if modulePath.len > 0:
      moduleInfos.add(ModuleInfo(name: moduleName, path: modulePath))
    else:
      stderr.writeLine("Warning: Could not find stdlib module: " & moduleName)
  
  # Second pass: parallel JSON generation using taskpools
  var pendingTasks: seq[FlowVar[bool]] = @[]
  let nimPath = index.sqlite.nimPath
  
  for info in moduleInfos:
    let modulePath = info.path
    let task = index.tp.spawn indexSingleModule(nimPath, modulePath)
    pendingTasks.add(task)
  
  # Wait for all generation tasks to complete
  var generationResults: seq[bool] = @[]
  for task in pendingTasks:
    generationResults.add(task.sync())
  
  # Third pass: load into SQLite
  var indexedCount = 0
  for i, info in moduleInfos:
    if generationResults[i]:
      # Parse JSON and add to SQLite
      let jsonPath = getJsonDocPath(info.path)
      let entries = parseJsonDoc(jsonPath)
      for sym in entries:
        index.sqlite.addSymbol(sym.name, sym.kind, info.path, sym.code, sym.description, sym.line, sym.col, "stdlib")
      if entries.len > 0:
        indexedCount.inc()
  
  index.isIndexed = true
  return indexedCount

proc loadOrBuildIndex*(index: StdlibIndex): int =
  ## Load existing index or build new one
  # Check if already indexed
  let stats = index.sqlite.getStats()
  if stats["totalSymbols"].getInt() > 0:
    stderr.writeLine("Using existing SQLite index with " & $stats["totalSymbols"].getInt() & " symbols")
    return stats["totalModules"].getInt()
  
  let indexedCount = scanAndIndexStdlib(index)
  if indexedCount > 0:
    stderr.writeLine("Indexed " & $indexedCount & " stdlib modules into SQLite")
  return indexedCount

proc indexStdlibModule*(index: StdlibIndex, moduleName: string): bool =
  ## Index a single stdlib module
  let modulePath = index.findModulePath(moduleName)
  if modulePath.len == 0:
    return false
  
  # Generate JSON doc
  if not indexSingleModule(index.sqlite.nimPath, modulePath):
    return false
  
  # Parse and add to SQLite
  let jsonPath = getJsonDocPath(modulePath)
  let entries = parseJsonDoc(jsonPath)
  for sym in entries:
    index.sqlite.addSymbol(sym.name, sym.kind, modulePath, sym.code, sym.description, sym.line, sym.col, "stdlib")
  
  return entries.len > 0

# Search wrappers
proc searchStdlib*(index: StdlibIndex, query: string, 
                   moduleFilter, typeFilter: Option[string],
                   maxResults: int): seq[SymbolResult] =
  ## Search stdlib for symbols using SQLite FTS
  return index.sqlite.search(query, moduleFilter, typeFilter, none(string), maxResults)

proc getProcInfo*(index: StdlibIndex, moduleName, procName: string): Option[SymbolResult] =
  ## Get procedure info by module and name
  # First ensure module is indexed
  if moduleName.len > 0:
    let modSymbols = index.sqlite.getModuleSymbols(moduleName)
    if modSymbols.len == 0:
      discard index.indexStdlibModule(moduleName)
  
  return index.sqlite.getSymbol(procName)

proc getModuleDocs*(index: StdlibIndex, moduleName: string): JsonNode =
  ## Get module documentation as JSON
  let symbols = index.sqlite.getModuleSymbols(moduleName)
  
  result = %*{
    "name": moduleName,
    "exports": symbols.len,
    "symbols": []
  }
  
  for sym in symbols:
    result["symbols"].add(%*{
      "name": sym.name,
      "kind": sym.kind,
      "description": sym.description
    })

proc isStdlibModule*(index: StdlibIndex, moduleName: string): bool =
  ## Check if a module is in stdlib
  return index.findModulePath(moduleName).len > 0

proc getStdlibModulePath*(index: StdlibIndex, moduleName: string): string =
  ## Get path to stdlib module
  return index.findModulePath(moduleName)

proc getStdlibIndexJson*(index: StdlibIndex): JsonNode =
  ## Get stdlib index statistics as JSON
  return index.sqlite.getStats()

proc close*(index: StdlibIndex) =
  ## Close the index and cleanup resources
  index.sqlite.close()
  index.tp.shutdown()
  deinitLock(index.indexLock)
