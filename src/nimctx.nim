# nimctx - Nim Context MCP Server
# Provides Nim stdlib and project dependencies context for AI assistants

import nimctx/[config, stdlib/indexer, project/manager, packages/indexer, version_compat]
import nimctx/utils/jsondoc_indexer
import nimcp
import std/[os, strutils, json, options, tables, osproc]

# Thread-safe state using closures
proc createServer(cfg: Config, stdlibIndex: StdlibIndex,
                  pkgRegistry: PackageRegistry,
                  projectManager: ProjectManager): McpServer =
  ## Create MCP server with configured tools
  result = newMcpServer("nimctx", "0.1.0")

  # Tool: Search stdlib and packages
  proc handleSearchStdlib(args: JsonNode): McpToolResult {.gcsafe, closure.} =
    let query = args["query"].getStr()
    let moduleFilter = if args.hasKey("moduleFilter"): some(args["moduleFilter"].getStr()) else: none(string)
    let kindFilter = if args.hasKey("symbolType"): some("sk" & args["symbolType"].getStr().capitalizeAscii()) else: none(string)
    let packageFilter = if args.hasKey("packageFilter"): some(args["packageFilter"].getStr()) else: none(string)

    var allResults: seq[JsonDocSymbol]

    # Search stdlib
    let stdlibResults = searchStdlib(stdlibIndex, query, moduleFilter, kindFilter, cfg.limits.maxSearchResults)
    allResults.add(stdlibResults)

    # Search packages if package filter specified or no results from stdlib
    if packageFilter.isSome or allResults.len == 0:
      let pkgResults = searchAllPackages(pkgRegistry, query, packageFilter, cfg.limits.maxSearchResults - allResults.len)
      allResults.add(pkgResults)

    var text: string
    if allResults.len == 0:
      text = "No results found for '" & query & "'"
    else:
      text = "Search results for '" & query & "':\n\n"

      # Group by source (stdlib vs package)
      var stdlibSyms: seq[JsonDocSymbol]
      var pkgSyms: seq[JsonDocSymbol]

      for r in allResults:
        # Check if it's from a package (module path contains package name)
        let isFromPackage = pkgRegistry.packages.len > 0 and
                            (packageFilter.isSome or r.modulePath.contains("pkgs2"))
        if isFromPackage:
          pkgSyms.add(r)
        else:
          stdlibSyms.add(r)

      if stdlibSyms.len > 0:
        text.add("### Standard Library\n\n")
        for r in stdlibSyms[0..<min(stdlibSyms.len, 10)]:
          text.add("• " & r.name & " (" & r.kind & ") in " & extractFilename(r.modulePath) & "\n")
          if r.description.len > 0:
            let shortDoc = r.description[0..<min(r.description.len, 100)]
            text.add("  " & shortDoc & "\n")
        text.add("\n")

      if pkgSyms.len > 0:
        text.add("### Packages\n\n")
        for r in pkgSyms[0..<min(pkgSyms.len, 10)]:
          text.add("• " & r.name & " (" & r.kind & ")\n")
          if r.description.len > 0:
            let shortDoc = r.description[0..<min(r.description.len, 100)]
            text.add("  " & shortDoc & "\n")
        text.add("\n")

    result = McpToolResult(content: @[createTextContent(text)])

  # Helper: Setup project manager with optional project root and auto-index dependencies
  proc setupProjectManager(projectRoot: string, autoIndex: bool = true): (ProjectManager, Option[McpToolResult]) =
    ## Returns (pm, errorResult). If errorResult.isSome, return it immediately.
    ## When autoIndex is true, project dependencies will be indexed for symbol search.
    if projectRoot.len > 0:
      let root = findProjectRoot(projectRoot)
      if root.len == 0:
        return (projectManager, some(McpToolResult(
          content: @[createTextContent("Error: No .nimble file found in: " & projectRoot)]
        )))
      let pm = projectManager.withProjectRoot(root)
      # Auto-index project dependencies only when requested
      if autoIndex:
        let deps = pm.getDependencies(true)
        for dep in deps:
          if not pkgRegistry.packages.hasKey(dep.name):
            let pkgPath = pm.getDependencyPath(dep.name)
            if pkgPath.len > 0:
              discard pkgRegistry.indexPackage(dep.name, pkgPath)
      return (pm, none(McpToolResult))
    return (projectManager, none(McpToolResult))

  # Tool: Get procedure signature (from stdlib or packages)
  proc handleGetProcSignature(args: JsonNode): McpToolResult {.gcsafe, closure.} =
    let procName = args["procName"].getStr()
    let pkgName = if args.hasKey("packageName"): some(args["packageName"].getStr()) else: none(string)
    let projectRoot = if args.hasKey("projectRoot"): args["projectRoot"].getStr() else: ""

    let (pm, err) = setupProjectManager(projectRoot)
    if err.isSome:
      return err.get()

    var text: string
    var found = false

    # First try packages if specified
    if pkgName.isSome:
      let pkgNameStr = pkgName.get()
      if pkgRegistry.packages.hasKey(pkgNameStr):
        let pkg = pkgRegistry.packages[pkgNameStr]
        let info = getPackageSymbol(pkg, procName)
        if info.isSome:
          text = formatSymbol(info.get())
          found = true

    # Then try stdlib
    if not found:
      let info = getProcInfo(stdlibIndex, "", procName)
      if info.isSome:
        text = formatSymbol(info.get())
        found = true

    if not found:
      text = "Error: Procedure '" & procName & "' not found"

    result = McpToolResult(content: @[createTextContent(text)])

  # Tool: List dependencies
  proc handleListDependencies(args: JsonNode): McpToolResult {.gcsafe, closure.} =
    let directOnly = if args.hasKey("directOnly"): args["directOnly"].getBool() else: false
    let projectRoot = if args.hasKey("projectRoot"): args["projectRoot"].getStr() else: ""
    
    let (pm, err) = setupProjectManager(projectRoot, autoIndex = false)
    if err.isSome:
      return err.get()
    
    let deps = pm.getDependencies(directOnly)

    var text = "## Project Dependencies\n\n"
    if deps.len == 0:
      text.add("No dependencies found.\n")
    else:
      for dep in deps:
        text.add("• **" & dep.name & "** " & dep.version)
        if dep.resolvedTo.len > 0:
          text.add(" (resolved: " & dep.resolvedTo & ")")
        text.add("\n")
        if dep.dependencies.len > 0:
          text.add("  depends on: " & dep.dependencies.join(", ") & "\n")

    result = McpToolResult(content: @[createTextContent(text)])

  # Tool: Get module docs (stdlib or package)
  proc handleGetModuleDocs(args: JsonNode): McpToolResult {.gcsafe, closure.} =
    let modulePath = args["modulePath"].getStr()
    let pkgName = if args.hasKey("packageName"): some(args["packageName"].getStr()) else: none(string)
    let projectRoot = if args.hasKey("projectRoot"): args["projectRoot"].getStr() else: ""

    let (pm, err) = setupProjectManager(projectRoot)
    if err.isSome:
      return err.get()

    var text = "## Module: " & modulePath & "\n\n"
    var found = false

    # Try package first if specified
    if pkgName.isSome:
      let pkgNameStr = pkgName.get()
      if pkgRegistry.packages.hasKey(pkgNameStr):
        let pkg = pkgRegistry.packages[pkgNameStr]
        # Find module by path
        for modName, modInfo in pkg.modules:
          if modName.contains(modulePath) or extractFilename(modInfo.origPath).replace(".nim", "") == modulePath:
            text.add("**Package:** " & pkgNameStr & "\n\n")
            text.add(modInfo.moduleDescription & "\n\n")
            text.add("### Exports\n\n")
            for entry in modInfo.entries:
              text.add("• " & entry.name & " (" & entry.kind & ")\n")
            found = true
            break

    # Try stdlib
    if not found:
      let stdlibModule = getModuleDocs(stdlibIndex, modulePath)
      if stdlibModule.isSome:
        let m = stdlibModule.get()
        text.add("**Source:** Standard Library\n\n")
        text.add(m.moduleDescription & "\n\n")
        text.add("### Exports\n\n")
        for entry in m.entries:
          text.add("• " & entry.name & " (" & entry.kind & ")\n")
        found = true

    if not found:
      text.add("Module not found.\n")

    result = McpToolResult(content: @[createTextContent(text)])

  # Tool: Resolve import
  proc handleResolveImport(args: JsonNode): McpToolResult {.gcsafe, closure.} =
    let importPath = args["importPath"].getStr()
    let projectRoot = if args.hasKey("projectRoot"): args["projectRoot"].getStr() else: ""
    
    let (pm, err) = setupProjectManager(projectRoot, autoIndex = false)
    if err.isSome:
      return err.get()

    var text = "## Import Resolution: `" & importPath & "`\n\n"

    # Check stdlib first
    if isStdlibModule(stdlibIndex, importPath):
      text.add("**Source:** Nim Standard Library\n\n")
      let path = getStdlibModulePath(stdlibIndex, importPath)
      text.add("**Path:** " & path & "\n")
    else:
      # Check if it's a package module (format: pkgname/module)
      let parts = importPath.split("/", maxsplit=1)
      if parts.len >= 1:
        let pkgName = parts[0]
        let pkgPath = pm.getDependencyPath(pkgName)
        if pkgPath.len > 0:
          text.add("**Source:** Package '" & pkgName & "'\n\n")
          text.add("**Path:** " & pkgPath & "\n")

          # Index the package if not already indexed
          if not pkgRegistry.packages.hasKey(pkgName):
            discard pkgRegistry.indexPackage(pkgName, pkgPath)
            text.add("\n*Package indexed for future queries*\n")
        else:
          text.add("**Source:** Unknown (not in stdlib or installed packages)\n")
      else:
        text.add("**Source:** Unknown\n")

    result = McpToolResult(content: @[createTextContent(text)])

  # Register all tools
  result.registerTool(
    McpTool(
      name: "search_stdlib",
      description: some("Search for functions, types, variables in Nim STANDARD LIBRARY ONLY. Use ONLY when user explicitly asks about: 'stdlib', 'standard library', or mentions specific stdlib modules like 'strutils', 'json', 'os', 'system', etc."),
      inputSchema: parseJson("""{"type": "object", "properties": {"query": {"type": "string", "description": "Search term like 'split string' or 'parse json'"}, "moduleFilter": {"type": "string", "description": "Optional: limit search to specific module like 'strutils'"}, "symbolType": {"type": "string", "description": "Optional: filter by type - proc, func, iterator, type, const, var"}, "packageFilter": {"type": "string", "description": "Optional: search in specific package"}}, "required": ["query"]}""")
    ),
    handleSearchStdlib
  )

  result.registerTool(
    McpTool(
      name: "get_proc_signature",
      description: some("Get detailed function signature from INDEXED packages only. Use ONLY when: 1) User mentions a specific function name AND 2) User explicitly mentions a stdlib module (strutils, json, etc.) or an already-indexed package."),
      inputSchema: parseJson("""{"type": "object", "properties": {"procName": {"type": "string", "description": "Function name like 'split' or 'parseJson'"}, "packageName": {"type": "string", "description": "Optional: package/module name like 'strutils' or 'json'"}, "projectRoot": {"type": "string", "description": "Optional: Path to project root directory containing .nimble file. Uses current directory if not provided."}}, "required": ["procName"]}""")
    ),
    handleGetProcSignature
  )

  result.registerTool(
    McpTool(
      name: "list_dependencies",
      description: some("List project dependencies from nimble. Use ONLY when user explicitly asks about project dependencies, nimble packages, or 'what packages does this project use'."),
      inputSchema: parseJson("""{"type": "object", "properties": {"directOnly": {"type": "boolean"}, "projectRoot": {"type": "string", "description": "Optional: Path to project root directory containing .nimble file. Uses current directory if not provided."}}, "required": []}""")
    ),
    handleListDependencies
  )

  result.registerTool(
    McpTool(
      name: "get_module_docs",
      description: some("Get documentation for a module from INDEXED packages only. Use ONLY when user explicitly asks about a specific module by name (e.g., 'strutils', 'json', 'system') and wants to see its documentation."),
      inputSchema: parseJson("""{"type": "object", "properties": {"modulePath": {"type": "string"}, "packageName": {"type": "string"}, "projectRoot": {"type": "string", "description": "Optional: Path to project root directory containing .nimble file. Uses current directory if not provided."}}, "required": ["modulePath"]}""")
    ),
    handleGetModuleDocs
  )

  result.registerTool(
    McpTool(
      name: "resolve_import",
      description: some("Find where an imported module comes from (stdlib path, nimble package location, or local file). Use when user asks: 'Where is X imported from?', 'Which package provides Y?', 'Find source of import Z'."),
      inputSchema: parseJson("""{"type": "object", "properties": {"importPath": {"type": "string", "description": "Import path like 'strutils', 'json', or 'mypackage/utils'"}, "projectRoot": {"type": "string", "description": "Optional: Path to project root directory containing .nimble file. Uses current directory if not provided."}}, "required": ["importPath"]}""")
    ),
    handleResolveImport
  )

  # Tool: Check version compatibility
  proc handleCheckVersionCompat(args: JsonNode): McpToolResult {.gcsafe, closure.} =
    let filePath = if args.hasKey("filePath"): args["filePath"].getStr() else: ""
    let testAll = if args.hasKey("testAllInstalled"): args["testAllInstalled"].getBool() else: true
    let updateNimble = if args.hasKey("updateNimble"): args["updateNimble"].getBool() else: false
    let projectRoot = if args.hasKey("projectRoot"): args["projectRoot"].getStr() else: ""

    let (pm, err) = setupProjectManager(projectRoot, autoIndex = false)
    if err.isSome:
      return err.get()

    # Determine file to test
    var targetFile = filePath
    var searchDir = if projectRoot.len > 0: projectRoot else: getCurrentDir()
    if targetFile.len == 0:
      # Try to find main nimble file
      let nimbleFiles = findNimbleFiles(searchDir)
      if nimbleFiles.len > 0:
        # Look for main source file from nimble config
        let nimblePath = nimbleFiles[0]
        let pkgName = extractFilename(nimblePath).replace(".nimble", "")
        # Try common locations
        let possiblePaths = [
          searchDir / "src" / (pkgName & ".nim"),
          searchDir / (pkgName & ".nim"),
          searchDir / "src" / "main.nim"
        ]
        for path in possiblePaths:
          if fileExists(path):
            targetFile = path
            break

    if targetFile.len == 0 or not fileExists(targetFile):
      result = McpToolResult(
        content: @[createTextContent("Error: No file to test. Please provide filePath or ensure there's a valid nimble project.")]
      )
      return result

    # Run compatibility check
    let report = checkVersionCompat(targetFile, @[], testAll)

    # Generate report
    var text = generateCompatReportMarkdown(report)

    # Update nimble file if requested
    if updateNimble and report.suggestedNimbleRequires.len > 0:
      let nimbleFiles = findNimbleFiles(searchDir)
      if nimbleFiles.len > 0:
        if updateNimbleRequires(nimbleFiles[0], report.suggestedNimbleRequires):
          text.add("\n✅ Updated nimble file with new requirements.\n")
        else:
          text.add("\n⚠️ Failed to update nimble file.\n")

    result = McpToolResult(content: @[createTextContent(text)])

  # Tool: List installed Nim versions
  proc handleListNimVersions(args: JsonNode): McpToolResult {.gcsafe, closure.} =
    let versions = getInstalledVersions()

    var text = "## Installed Nim Versions (via choosenim)\n\n"
    for ver in versions:
      text.add("- " & ver.version)
      if ver.isDevel:
        text.add(" (development)")
      text.add("\n")

    # Also show current version
    let (current, _) = execCmdEx("nim --version | head -1")
    text.add("\n**Current:** " & current.strip() & "\n")

    result = McpToolResult(content: @[createTextContent(text)])

  result.registerTool(
    McpTool(
      name: "check_version_compat",
      description: some("Check if Nim code works with different compiler versions (1.6, 2.0, 2.2, devel). Use when user asks: 'Will this work on Nim X?', 'Check version compatibility', 'What is the minimum Nim version required?', 'Test on multiple Nim versions'."),
      inputSchema: parseJson("""{"type": "object", "properties": {"filePath": {"type": "string", "description": "Path to .nim file to test. Auto-detected from nimble project if not provided."}, "testAllInstalled": {"type": "boolean", "description": "Test all installed Nim versions via choosenim. Default: true"}, "updateNimble": {"type": "boolean", "description": "If true, automatically update nimble file's 'requires nim >= X.X.X' based on test results. Only modifies the Nim version requirement, not other dependencies. Default: false"}, "projectRoot": {"type": "string", "description": "Optional: Path to project root directory containing .nimble file. Uses current directory if not provided."}}, "required": []}""")
    ),
    handleCheckVersionCompat
  )

  result.registerTool(
    McpTool(
      name: "list_nim_versions",
      description: some("List all Nim versions installed via choosenim (1.6.x, 2.0.x, 2.2.x, devel, etc). Use when user asks: 'What Nim versions do I have?', 'List installed Nim versions', 'Show available Nim compilers'."),
      inputSchema: parseJson("""{"type": "object", "properties": {}}""")
    ),
    handleListNimVersions
  )

proc main() =
  # Load configuration
  let cfg = loadConfig()

  # Initialize stdlib indexer
  var stdlibIndex: StdlibIndex
  if cfg.indexing.enableStdlibIndex:
    stdlibIndex = newStdlibIndex(cfg.nim.stdlibPath, cfg.indexing.cacheDir, cfg.nim.nimPath)
    try:
      let indexed = loadOrBuildIndex(stdlibIndex)
      stderr.writeLine("Indexed " & $indexed & " stdlib modules")
    except:
      stderr.writeLine("Warning: Failed to load/build stdlib index: " & getCurrentExceptionMsg())

  # Initialize package registry
  let pkgCacheDir = cfg.indexing.cacheDir / "packages"
  createDir(pkgCacheDir)
  let pkgRegistry = newPackageRegistry(pkgCacheDir, cfg.nim.nimPath)

  # Initialize project manager (only if .nimble file found in current dir)
  let projectRoot = findProjectRoot(getCurrentDir())
  let projectManager = if projectRoot.len > 0:
    newProjectManager(cfg.nim.nimblePath, projectRoot)
  else:
    newProjectManager(cfg.nim.nimblePath, "")  # Empty project manager

  # Create server
  let server = createServer(cfg, stdlibIndex, pkgRegistry, projectManager)

  # Run with stdio transport
  let transport = newStdioTransport()
  transport.serve(server)

when isMainModule:
  main()
