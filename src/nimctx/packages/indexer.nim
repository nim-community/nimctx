# Dependency package indexing using SQLite with FTS support

import std/[os, strutils, tables, options, times, cpuinfo, json]
import ../utils/[cache, sqlite_indexer, indexing]
import taskpools

export sqlite_indexer

type
  PackageIndex* = SqliteIndex
  PackageRegistry* = ref object
    packages*: Table[string, PackageIndex]
    cacheDir*: string
    globalSearchCache*: MemoryCache[seq[SymbolResult]]
    nimPath*: string
    tp*: TaskPool

proc newPackageIndex*(name, version, path, cacheDir, nimPath: string): PackageIndex =
  ## Create a new package index with SQLite backend
  let pkgCacheDir = cacheDir / name
  createDir(pkgCacheDir)
  let dbPath = pkgCacheDir / "index.db"
  result = newSqliteIndex(dbPath, nimPath)

proc newPackageRegistry*(cacheDir: string, nimPath: string = ""): PackageRegistry =
  ## Create a new package registry with parallel processing support
  new(result)
  result.cacheDir = cacheDir
  result.packages = initTable[string, PackageIndex]()
  result.globalSearchCache = newMemoryCache[seq[SymbolResult]](maxSize = 500, defaultTtl = initDuration(minutes = 5))
  result.nimPath = if nimPath.len > 0: nimPath else: findExe("nim")
  
  # Create thread pool with number of CPUs
  let numThreads = max(2, cpuinfo.countProcessors())
  result.tp = TaskPool.new(numThreads)

proc indexPackage*(registry: PackageRegistry, pkgName, pkgPath: string): PackageIndex =
  ## Index a package and add to registry using parallel processing
  # Extract version from path (e.g., pkgname-1.0.0-hash)
  var version = "unknown"
  let dirName = extractFilename(pkgPath)
  let parts = dirName.split("-")
  if parts.len >= 2:
    version = parts[1]
  
  let pkg = newPackageIndex(pkgName, version, pkgPath, registry.cacheDir, registry.nimPath)
  
  # Clear existing data for this package
  pkg.clear()
  
  # First pass: collect all .nim files to process
  var modulePaths: seq[string] = @[]
  if dirExists(pkgPath):
    for file in walkDirRec(pkgPath):
      if file.endsWith(".nim") and not file.endsWith("_test.nim") and not file.contains("/tests/"):
        modulePaths.add(file)
  
  # Second pass: parallel JSON generation using taskpools
  var pendingTasks: seq[FlowVar[bool]] = @[]
  let nimPath = registry.nimPath
  
  for modulePath in modulePaths:
    let mpath = modulePath
    let task = registry.tp.spawn indexSingleModule(nimPath, mpath)
    pendingTasks.add(task)
  
  # Wait for all generation tasks to complete
  var generationResults: seq[bool] = @[]
  for task in pendingTasks:
    generationResults.add(task.sync())
  
  # Third pass: load into SQLite
  for i, modulePath in modulePaths:
    if generationResults[i]:
      let jsonPath = modulePath.parentDir() / "htmldocs" / extractFilename(modulePath).replace(".nim", "") & ".json"
      if fileExists(jsonPath):
        try:
          let content = readFile(jsonPath)
          let json = parseJson(content)
          
          if json.hasKey("entries") and json["entries"].kind == JArray:
            for entry in json["entries"]:
              var symName = ""
              var symKind = ""
              var symCode = ""
              var symDesc = ""
              var symLine = 0
              var symCol = 0
              
              if entry.hasKey("name"):
                symName = entry["name"].getStr()
              if entry.hasKey("type"):
                symKind = entry["type"].getStr()
              if entry.hasKey("code"):
                symCode = entry["code"].getStr()
              if entry.hasKey("description"):
                symDesc = entry["description"].getStr()
              if entry.hasKey("line"):
                symLine = entry["line"].getInt()
              if entry.hasKey("col"):
                symCol = entry["col"].getInt()
              
              pkg.addSymbol(symName, symKind, modulePath, symCode, symDesc, symLine, symCol, pkgName)
        except:
          stderr.writeLine("Error parsing JSON for " & modulePath & ": " & getCurrentExceptionMsg())
  
  registry.packages[pkgName] = pkg
  return pkg

proc getOrIndexPackage*(registry: PackageRegistry, pkgName, pkgPath: string): PackageIndex =
  ## Get cached package index or create new one
  if registry.packages.hasKey(pkgName):
    return registry.packages[pkgName]
  
  return registry.indexPackage(pkgName, pkgPath)

proc searchPackage*(pkg: PackageIndex, query: string, maxResults: int): seq[SymbolResult] =
  ## Search within a single package
  return pkg.search(query, none(string), none(string), some(pkg.dbPath.parentDir().extractFilename), maxResults)

proc searchAllPackages*(registry: PackageRegistry, query: string, 
                        pkgFilter: Option[string] = none(string),
                        maxResults: int = 20): seq[SymbolResult] =
  ## Search across all indexed packages
  # Generate cache key
  var cacheKey = query.toLowerAscii() & ":" & $maxResults
  if pkgFilter.isSome:
    cacheKey &= ":pkg:" & pkgFilter.get()
  
  # Check global cache
  let cached = registry.globalSearchCache.get(cacheKey)
  if cached.isSome:
    return cached.get()
  
  var matches: seq[SymbolResult]
  
  # Search specific package or all packages
  if pkgFilter.isSome:
    let pkgName = pkgFilter.get()
    if registry.packages.hasKey(pkgName):
      matches = registry.packages[pkgName].search(query, none(string), none(string), none(string), maxResults)
  else:
    for name, pkg in registry.packages:
      let pkgMatches = pkg.search(query, none(string), none(string), none(string), maxResults - matches.len)
      matches.add(pkgMatches)
      if matches.len >= maxResults:
        break
  
  result = matches[0..<min(matches.len, maxResults)]
  registry.globalSearchCache.set(cacheKey, result)

proc getPackageModule*(pkg: PackageIndex, moduleName: string): seq[SymbolResult] =
  ## Get module info from package
  return pkg.getModuleSymbols(moduleName)

proc getPackageSymbol*(pkg: PackageIndex, symbolName: string): Option[SymbolResult] =
  ## Get symbol info from package
  return pkg.getSymbol(symbolName)

proc listPackageModules*(pkg: PackageIndex): seq[string] =
  ## List all module names in package
  return pkg.listModules()

proc listPackageSymbols*(pkg: PackageIndex): seq[string] =
  ## List all symbol names in package
  return pkg.listSymbols()
