# JSONDoc-based indexer using `nim jsondoc` command

import std/[os, strutils, json, options, times, tables, osproc]
import cache

type
  JsonDocSymbolKind* = enum
    jskConst, jskLet, jskVar, jskProc, jskFunc, jskMethod,
    jskIterator, jskConverter, jskMacro, jskTemplate, jskType,
    jskEnumField, jskParam, jskGenericParam
  
  JsonDocArgument* = object
    name*: string
    typ*: string
    defaultValue*: Option[string]
  
  JsonDocSignature* = object
    returnType*: Option[string]
    arguments*: seq[JsonDocArgument]
    pragmas*: seq[string]
  
  JsonDocSymbol* = object
    name*: string
    kind*: string
    line*: int
    col*: int
    code*: string
    signature*: Option[JsonDocSignature]
    description*: string
    modulePath*: string
  
  JsonDocModule* = object
    origPath*: string
    nimble*: string
    moduleDescription*: string
    entries*: seq[JsonDocSymbol]
  
  JsonDocIndex* = ref object
    cacheDir*: string
    nimPath*: string
    modules*: Table[string, JsonDocModule]
    symbolTable*: Table[string, seq[JsonDocSymbol]]
    searchCache*: MemoryCache[seq[JsonDocSymbol]]

proc kindFromString(s: string): JsonDocSymbolKind =
  ## Convert string kind to enum
  case s
  of "skConst": jskConst
  of "skLet": jskLet
  of "skVar": jskVar
  of "skProc": jskProc
  of "skFunc": jskFunc
  of "skMethod": jskMethod
  of "skIterator": jskIterator
  of "skConverter": jskConverter
  of "skMacro": jskMacro
  of "skTemplate": jskTemplate
  of "skType": jskType
  of "skEnumField": jskEnumField
  of "skParam": jskParam
  of "skGenericParam": jskGenericParam
  else: jskProc  # default

proc newJsonDocIndex*(cacheDir, nimPath: string): JsonDocIndex =
  ## Create a new JSONDoc-based index
  new(result)
  result.cacheDir = cacheDir
  result.nimPath = nimPath
  result.modules = initTable[string, JsonDocModule]()
  result.symbolTable = initTable[string, seq[JsonDocSymbol]]()
  result.searchCache = newMemoryCache[seq[JsonDocSymbol]](maxSize = 500, defaultTtl = initDuration(minutes = 10))

proc getModuleCachePath(index: JsonDocIndex, modulePath: string): string =
  ## Get the cache path for a module
  # nim jsondoc generates output in htmldocs subdirectory of the input file's directory
  let moduleDir = modulePath.parentDir()
  let moduleName = extractFilename(modulePath).replace(".nim", "")
  return moduleDir / "htmldocs" / moduleName & ".json"

proc generateJsonDoc*(index: JsonDocIndex, modulePath: string): bool =
  ## Generate JSON doc for a module using `nim jsondoc`
  if not fileExists(modulePath):
    return false
  
  let cachePath = index.getModuleCachePath(modulePath)
  
  # Check if cached version is fresh
  if fileExists(cachePath):
    let cacheTime = getFileInfo(cachePath).lastWriteTime
    let moduleTime = getFileInfo(modulePath).lastWriteTime
    if cacheTime > moduleTime:
      return true  # Cache is fresh
  
  # Generate jsondoc (output goes to htmldocs subdirectory of module's directory)
  let cmd = index.nimPath & " jsondoc " & quoteShell(modulePath)
  let (output, exitCode) = execCmdEx(cmd)
  
  if exitCode != 0:
    stderr.writeLine("Warning: nim jsondoc failed for " & modulePath & ": " & output)
    return false
  
  return true

proc parseSignature(json: JsonNode): Option[JsonDocSignature] =
  ## Parse signature from JSON
  if json.kind == JNull:
    return none(JsonDocSignature)
  
  var sig: JsonDocSignature
  
  # Parse return type
  if json.hasKey("return"):
    sig.returnType = some(json["return"].getStr())
  
  # Parse arguments
  if json.hasKey("arguments") and json["arguments"].kind == JArray:
    for arg in json["arguments"]:
      var argument: JsonDocArgument
      if arg.hasKey("name"):
        argument.name = arg["name"].getStr()
      if arg.hasKey("type"):
        argument.typ = arg["type"].getStr()
      if arg.hasKey("default"):
        argument.defaultValue = some(arg["default"].getStr())
      sig.arguments.add(argument)
  
  # Parse pragmas
  if json.hasKey("pragmas") and json["pragmas"].kind == JArray:
    for pragma in json["pragmas"]:
      sig.pragmas.add(pragma.getStr())
  
  return some(sig)

proc loadModuleFromJson*(index: JsonDocIndex, modulePath: string): bool =
  ## Load module data from generated JSON
  let cachePath = index.getModuleCachePath(modulePath)
  
  if not fileExists(cachePath):
    # Try to generate it
    if not index.generateJsonDoc(modulePath):
      return false
  
  if not fileExists(cachePath):
    return false
  
  try:
    let content = readFile(cachePath)
    let json = parseJson(content)
    
    var module: JsonDocModule
    
    if json.hasKey("orig"):
      module.origPath = json["orig"].getStr()
    if json.hasKey("nimble"):
      module.nimble = json["nimble"].getStr()
    if json.hasKey("moduleDescription"):
      module.moduleDescription = json["moduleDescription"].getStr()
    
    # Parse entries
    if json.hasKey("entries") and json["entries"].kind == JArray:
      for entry in json["entries"]:
        var symbol: JsonDocSymbol
        
        if entry.hasKey("name"):
          symbol.name = entry["name"].getStr()
        if entry.hasKey("type"):
          symbol.kind = entry["type"].getStr()
        if entry.hasKey("line"):
          symbol.line = entry["line"].getInt()
        if entry.hasKey("col"):
          symbol.col = entry["col"].getInt()
        if entry.hasKey("code"):
          symbol.code = entry["code"].getStr()
        if entry.hasKey("signature"):
          symbol.signature = parseSignature(entry["signature"])
        if entry.hasKey("description"):
          symbol.description = entry["description"].getStr()
        
        symbol.modulePath = modulePath
        module.entries.add(symbol)
        
        # Add to symbol table
        if not index.symbolTable.hasKey(symbol.name):
          index.symbolTable[symbol.name] = @[]
        index.symbolTable[symbol.name].add(symbol)
    
    let moduleName = extractFilename(modulePath).replace(".nim", "")
    index.modules[moduleName] = module
    
    return true
  except:
    stderr.writeLine("Error parsing JSON doc for " & modulePath & ": " & getCurrentExceptionMsg())
    return false

proc searchJsonDoc*(index: JsonDocIndex, query: string, 
                    moduleFilter: Option[string] = none(string),
                    kindFilter: Option[string] = none(string),
                    maxResults: int = 20): seq[JsonDocSymbol] =
  ## Search for symbols in the index
  # Check cache
  var cacheKey = query.toLowerAscii() & ":" & $maxResults
  if moduleFilter.isSome:
    cacheKey &= ":mod:" & moduleFilter.get()
  if kindFilter.isSome:
    cacheKey &= ":kind:" & kindFilter.get()
  
  let cached = index.searchCache.get(cacheKey)
  if cached.isSome:
    return cached.get()
  
  let queryLower = query.toLowerAscii()
  
  # Collect all symbols from symbolTable
  var allSymbols: seq[JsonDocSymbol]
  for symbols in index.symbolTable.values:
    allSymbols.add(symbols)
  
  # Filter by query (name or description), module, and kind
  result = allSymbols.filterIt(
    (queryLower in it.name.toLowerAscii() or queryLower in it.description.toLowerAscii()) and
    (moduleFilter.isNone or extractFilename(it.modulePath).replace(".nim", "") == moduleFilter.get()) and
    (kindFilter.isNone or it.kind == kindFilter.get())
  )[0 ..< min(maxResults, allSymbols.len)]
  
  index.searchCache.set(cacheKey, result)

proc getSymbol*(index: JsonDocIndex, name: string): Option[JsonDocSymbol] =
  ## Get symbol by name
  if index.symbolTable.hasKey(name):
    if index.symbolTable[name].len > 0:
      return some(index.symbolTable[name][0])
  return none(JsonDocSymbol)

proc getModule*(index: JsonDocIndex, name: string): Option[JsonDocModule] =
  ## Get module by name
  if index.modules.hasKey(name):
    return some(index.modules[name])
  return none(JsonDocModule)

proc formatSymbol*(sym: JsonDocSymbol): string =
  ## Format symbol for display
  result = "## " & sym.name & "\n\n"
  result.add("**Kind:** " & sym.kind & "\n\n")
  result.add("**Signature:**\n```nim\n" & sym.code & "\n```\n\n")
  
  if sym.signature.isSome:
    let sig = sym.signature.get()
    if sig.returnType.isSome:
      result.add("**Returns:** " & sig.returnType.get() & "\n\n")
    if sig.arguments.len > 0:
      result.add("**Arguments:**\n")
      for arg in sig.arguments:
        result.add("- `" & arg.name & "`: " & arg.typ)
        if arg.defaultValue.isSome:
          result.add(" = " & arg.defaultValue.get())
        result.add("\n")
      result.add("\n")
  
  if sym.description.len > 0:
    result.add("**Description:**\n" & sym.description & "\n")
