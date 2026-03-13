# Configuration management for nimctx

import std/[os, json, strutils]

type
  NimConfig* = object
    nimPath*: string
    nimblePath*: string
    stdlibPath*: string
  
  IndexingConfig* = object
    enableStdlibIndex*: bool
    enableDepIndex*: bool
    cacheDir*: string
  
  LimitsConfig* = object
    maxSearchResults*: int
    maxDocLength*: int
  
  Config* = object
    transport*: string
    nim*: NimConfig
    indexing*: IndexingConfig
    limits*: LimitsConfig

proc getDefaultNimPath(): string =
  ## Get the path to the Nim compiler executable
  ## Uses getCurrentCompilerExe() to get the compiler used to build this program
  result = getCurrentCompilerExe()
  if result.len == 0 or not fileExists(result):
    # Fallback to finding nim in PATH
    result = findExe("nim")
  if result.len == 0 or not fileExists(result):
    # Fallback to common locations
    when defined(macosx):
      result = "/usr/local/bin/nim"
    elif defined(linux):
      result = "/usr/bin/nim"
    else:
      result = "nim"

proc getDefaultNimblePath(): string =
  let nimble = findExe("nimble")
  if nimble.len > 0:
    return nimble
  when defined(macosx):
    return "/usr/local/bin/nimble"
  elif defined(linux):
    return "/usr/bin/nimble"
  else:
    return "nimble"

proc getDefaultStdlibPath(): string =
  ## Get the stdlib path from the compiler location
  ## The stdlib is typically at <nim-root>/lib where <nim-root> is the parent of the bin directory
  let nimPath = getDefaultNimPath()
  if nimPath.len > 0 and fileExists(nimPath):
    # Go from <nim-root>/bin/nim to <nim-root>/lib
    let nimBinDir = nimPath.parentDir()
    let nimRoot = nimBinDir.parentDir()
    let libPath = nimRoot / "lib"
    if fileExists(libPath / "system.nim"):
      return libPath
  
  # Fallback: Try to find stdlib in choosenim
  let home = getHomeDir()
  let choosenimDir = home / ".choosenim" / "toolchains"
  if dirExists(choosenimDir):
    # Prefer devel version
    let develPath = choosenimDir / "nim-#devel" / "lib"
    if fileExists(develPath / "system.nim"):
      return develPath
    
    # Try other versions
    for kind, path in walkDir(choosenimDir):
      if kind == pcDir and path.extractFilename().startsWith("nim-"):
        let libPath = path / "lib"
        if fileExists(libPath / "system.nim"):
          return libPath
  
  # Fallback to system paths
  let systemPaths = [
    "/usr/local/lib/nim/lib",
    "/usr/lib/nim/lib",
    "/opt/homebrew/lib/nim/lib",
  ]
  
  for path in systemPaths:
    if dirExists(path) and fileExists(path / "system.nim"):
      return path
  
  return ""

proc getDefaultCacheDir(): string =
  let cacheBase = getCacheDir("nimctx")
  return cacheBase

proc loadConfig*(configPath: string = ""): Config =
  ## Load configuration from file or use defaults
  result = Config(
    transport: "stdio",
    nim: NimConfig(
      nimPath: getDefaultNimPath(),
      nimblePath: getDefaultNimblePath(),
      stdlibPath: getDefaultStdlibPath()
    ),
    indexing: IndexingConfig(
      enableStdlibIndex: true,
      enableDepIndex: true,
      cacheDir: getDefaultCacheDir()
    ),
    limits: LimitsConfig(
      maxSearchResults: 20,
      maxDocLength: 10000
    )
  )
  
  # Try to load from config file
  var cfgFile = configPath
  if cfgFile.len == 0:
    # Look for config in standard locations
    let cwdConfig = getCurrentDir() / "nimctx.json"
    let homeConfig = getConfigDir() / "nimctx" / "config.json"
    
    if fileExists(cwdConfig):
      cfgFile = cwdConfig
    elif fileExists(homeConfig):
      cfgFile = homeConfig
  
  if cfgFile.len > 0 and fileExists(cfgFile):
    try:
      let json = parseFile(cfgFile)
      
      if json.hasKey("transport"):
        result.transport = json["transport"].getStr()
      
      if json.hasKey("nim"):
        let nim = json["nim"]
        if nim.hasKey("nimPath"):
          result.nim.nimPath = nim["nimPath"].getStr()
        if nim.hasKey("nimblePath"):
          result.nim.nimblePath = nim["nimblePath"].getStr()
        if nim.hasKey("stdlibPath"):
          result.nim.stdlibPath = nim["stdlibPath"].getStr()
      
      if json.hasKey("indexing"):
        let idx = json["indexing"]
        if idx.hasKey("enableStdlibIndex"):
          result.indexing.enableStdlibIndex = idx["enableStdlibIndex"].getBool()
        if idx.hasKey("enableDepIndex"):
          result.indexing.enableDepIndex = idx["enableDepIndex"].getBool()
        if idx.hasKey("cacheDir"):
          result.indexing.cacheDir = idx["cacheDir"].getStr()
      
      if json.hasKey("limits"):
        let lim = json["limits"]
        if lim.hasKey("maxSearchResults"):
          result.limits.maxSearchResults = lim["maxSearchResults"].getInt()
        if lim.hasKey("maxDocLength"):
          result.limits.maxDocLength = lim["maxDocLength"].getInt()
    except:
      stderr.writeLine("Warning: Failed to load config file: " & cfgFile)
  
  # Ensure cache directory exists
  createDir(result.indexing.cacheDir)
