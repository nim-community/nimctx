# Standard library indexing using nim jsondoc with parallel processing

import std/[os, json, tables, options]
import std/cpuinfo
import taskpools
import ../utils/[jsondoc_indexer, indexing]

export jsondoc_indexer

type
  StdlibIndex* = ref object
    jsonIndex*: JsonDocIndex
    stdlibPath*: string
    tp*: TaskPool

  ModuleTaskResult = object
    moduleName: string
    modulePath: string
    success: bool

proc newStdlibIndex*(stdlibPath, cacheDir: string; nimPath: string = ""): StdlibIndex =
  ## Create a new stdlib index with parallel processing support
  var actualNimPath = nimPath
  
  if actualNimPath.len == 0:
    actualNimPath = stdlibPath.parentDir() / "bin" / "nim"
  
  if actualNimPath.len == 0 or not fileExists(actualNimPath):
    actualNimPath = findExe("nim")
  
  if actualNimPath.len == 0 or not fileExists(actualNimPath):
    raise newException(OSError, "nim binary not found for stdlib: " & stdlibPath)
  
  let jsonCacheDir = cacheDir / "jsondoc"
  createDir(jsonCacheDir)
  
  # Create thread pool with number of CPUs
  let numThreads = max(2, cpuinfo.countProcessors())
  
  result = StdlibIndex(
    jsonIndex: newJsonDocIndex(jsonCacheDir, actualNimPath),
    stdlibPath: stdlibPath,
    tp: TaskPool.new(numThreads)
  )

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
  if not dirExists(index.stdlibPath):
    stderr.writeLine("Warning: Stdlib path not found: " & index.stdlibPath)
    return 0
  
  # Core modules to index (most commonly used)
  # Note: os.nim, macros.nim, typeinfo.nim are temporarily excluded due to nim jsondoc bugs
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
  let nimPath = index.jsonIndex.nimPath  # Capture locally for spawn
  
  for info in moduleInfos:
    let modulePath = info.path
    let task = index.tp.spawn indexSingleModule(nimPath, modulePath)
    pendingTasks.add(task)
  
  # Wait for all generation tasks to complete
  var generationResults: seq[bool] = @[]
  for task in pendingTasks:
    generationResults.add(task.sync())
  
  # Third pass: sequential loading (thread-safe, modifies shared state)
  var indexedCount = 0
  for i, info in moduleInfos:
    if generationResults[i]:
      if index.jsonIndex.loadModuleFromJson(info.path):
        indexedCount.inc()
  
  return indexedCount

proc loadOrBuildIndex*(index: StdlibIndex): int =
  ## Load existing index or build new one
  let indexedCount = scanAndIndexStdlib(index)
  if indexedCount > 0:
    stderr.writeLine("Indexed " & $indexedCount & " stdlib modules")
  return indexedCount

proc indexStdlibModule*(index: StdlibIndex, moduleName: string): bool =
  ## Index a single stdlib module
  let modulePath = index.findModulePath(moduleName)
  if modulePath.len == 0:
    return false
  return index.jsonIndex.loadModuleFromJson(modulePath)

# Backwards compatibility wrappers
proc searchStdlib*(index: StdlibIndex, query: string, 
                   moduleFilter, typeFilter: Option[string],
                   maxResults: int): seq[JsonDocSymbol] =
  ## Search stdlib for symbols
  return searchJsonDoc(index.jsonIndex, query, moduleFilter, typeFilter, maxResults)

proc getProcInfo*(index: StdlibIndex, moduleName, procName: string): Option[JsonDocSymbol] =
  ## Get procedure info by module and name
  if not index.jsonIndex.modules.hasKey(moduleName):
    discard index.indexStdlibModule(moduleName)
  
  return getSymbol(index.jsonIndex, procName)

proc getModuleDocs*(index: StdlibIndex, moduleName: string): Option[JsonDocModule] =
  ## Get module documentation
  if not index.jsonIndex.modules.hasKey(moduleName):
    discard index.indexStdlibModule(moduleName)
  
  return getModule(index.jsonIndex, moduleName)

proc isStdlibModule*(index: StdlibIndex, moduleName: string): bool =
  ## Check if a module is in stdlib
  return index.findModulePath(moduleName).len > 0

proc getStdlibModulePath*(index: StdlibIndex, moduleName: string): string =
  ## Get path to stdlib module
  return index.findModulePath(moduleName)

proc getStdlibIndexJson*(index: StdlibIndex): JsonNode =
  ## Get stdlib index as JSON
  result = %*{ "modules": {} }
  
  for name, module in index.jsonIndex.modules:
    result["modules"][name] = %*{
      "path": module.origPath,
      "doc": module.moduleDescription[0..<min(module.moduleDescription.len, 200)],
      "exports": module.entries.len
    }
