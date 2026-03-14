# Dependency package indexing using nim jsondoc with parallel processing

import std/[os, strutils, tables, options, times, cpuinfo, osproc]
import ../utils/[cache, jsondoc_indexer]
import taskpools

export jsondoc_indexer

type
  PackageIndex* = JsonDocIndex
  PackageRegistry* = ref object
    packages*: Table[string, PackageIndex]
    cacheDir*: string
    globalSearchCache*: MemoryCache[seq[JsonDocSymbol]]
    nimPath*: string
    tp*: TaskPool

proc newPackageIndex*(name, version, path, cacheDir, nimPath: string): PackageIndex =
  ## Create a new package index
  let pkgCacheDir = cacheDir / name
  createDir(pkgCacheDir)
  result = newJsonDocIndex(pkgCacheDir, nimPath)

proc newPackageRegistry*(cacheDir: string, nimPath: string = ""): PackageRegistry =
  ## Create a new package registry with parallel processing support
  new(result)
  result.cacheDir = cacheDir
  result.packages = initTable[string, PackageIndex]()
  result.globalSearchCache = newMemoryCache[seq[JsonDocSymbol]](maxSize = 500, defaultTtl = initDuration(minutes = 5))
  result.nimPath = if nimPath.len > 0: nimPath else: findExe("nim")
  
  # Create thread pool with number of CPUs
  let numThreads = max(2, cpuinfo.countProcessors())
  result.tp = TaskPool.new(numThreads)

proc indexSingleModule(nimPath, modulePath: string): bool {.gcsafe, raises: [].} =
  ## Generate JSON doc for a single module (runs in worker thread)
  # This delegates to the jsondoc_indexer's generateJsonDoc logic
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

proc indexPackage*(registry: PackageRegistry, pkgName, pkgPath: string): PackageIndex =
  ## Index a package and add to registry using parallel processing
  # Extract version from path (e.g., pkgname-1.0.0-hash)
  var version = "unknown"
  let dirName = extractFilename(pkgPath)
  let parts = dirName.split("-")
  if parts.len >= 2:
    version = parts[1]
  
  let pkg = newPackageIndex(pkgName, version, pkgPath, registry.cacheDir, registry.nimPath)
  
  # First pass: collect all .nim files to process
  var modulePaths: seq[string] = @[]
  if dirExists(pkgPath):
    for file in walkDirRec(pkgPath):
      if file.endsWith(".nim") and not file.endsWith("_test.nim") and not file.contains("/tests/"):
        modulePaths.add(file)
  
  # Second pass: parallel JSON generation using taskpools
  var pendingTasks: seq[FlowVar[bool]] = @[]
  let nimPath = registry.nimPath  # Capture locally for spawn
  
  for modulePath in modulePaths:
    let mpath = modulePath  # Local copy for spawn capture
    let task = registry.tp.spawn indexSingleModule(nimPath, mpath)
    pendingTasks.add(task)
  
  # Wait for all generation tasks to complete
  var generationResults: seq[bool] = @[]
  for task in pendingTasks:
    generationResults.add(task.sync())
  
  # Third pass: sequential loading (thread-safe, modifies shared state)
  for i, modulePath in modulePaths:
    if generationResults[i]:
      discard pkg.loadModuleFromJson(modulePath)
  
  registry.packages[pkgName] = pkg
  return pkg

proc getOrIndexPackage*(registry: PackageRegistry, pkgName, pkgPath: string): PackageIndex =
  ## Get cached package index or create new one
  if registry.packages.hasKey(pkgName):
    return registry.packages[pkgName]
  
  return registry.indexPackage(pkgName, pkgPath)

proc searchPackage*(pkg: PackageIndex, query: string, maxResults: int): seq[JsonDocSymbol] =
  ## Search within a single package
  return searchJsonDoc(pkg, query, none(string), none(string), maxResults)

proc searchAllPackages*(registry: PackageRegistry, query: string, 
                        pkgFilter: Option[string] = none(string),
                        maxResults: int = 20): seq[JsonDocSymbol] =
  ## Search across all indexed packages
  # Generate cache key
  var cacheKey = query.toLowerAscii() & ":" & $maxResults
  if pkgFilter.isSome:
    cacheKey &= ":pkg:" & pkgFilter.get()
  
  # Check global cache
  let cached = registry.globalSearchCache.get(cacheKey)
  if cached.isSome:
    return cached.get()
  
  var matches: seq[JsonDocSymbol]
  
  # Search specific package or all packages
  if pkgFilter.isSome:
    let pkgName = pkgFilter.get()
    if registry.packages.hasKey(pkgName):
      matches = searchJsonDoc(registry.packages[pkgName], query, none(string), none(string), maxResults)
  else:
    for name, pkg in registry.packages:
      let pkgMatches = searchJsonDoc(pkg, query, none(string), none(string), maxResults - matches.len)
      matches.add(pkgMatches)
      if matches.len >= maxResults:
        break
  
  result = matches[0..<min(matches.len, maxResults)]
  registry.globalSearchCache.set(cacheKey, result)

proc getPackageModule*(pkg: PackageIndex, moduleName: string): Option[JsonDocModule] =
  ## Get module info from package
  return getModule(pkg, moduleName)

proc getPackageSymbol*(pkg: PackageIndex, symbolName: string): Option[JsonDocSymbol] =
  ## Get symbol info from package
  return getSymbol(pkg, symbolName)

proc listPackageModules*(pkg: PackageIndex): seq[string] =
  ## List all module names in package
  for name in pkg.modules.keys:
    result.add(name)

proc listPackageSymbols*(pkg: PackageIndex): seq[string] =
  ## List all symbol names in package
  for name in pkg.symbolTable.keys:
    result.add(name)
