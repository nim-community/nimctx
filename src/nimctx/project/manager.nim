# Project dependency management

import std/[os, strutils, json, options, tables, hashes, times, osproc]

type
  Dependency* = object
    name*: string
    version*: string
    description*: string
    resolvedTo*: string
    dependencies*: seq[string]
  
  ProjectInfo* = object
    name*: string
    version*: string
    author*: string
    description*: string
    license*: string
    requires*: seq[Dependency]
    srcDir*: string
    bin*: seq[string]
  
  ProjectManager* = object
    nimblePath*: string
    projectRoot*: string
    cache*: Table[string, ProjectInfo]
    lastUpdate*: Time

proc newProjectManager*(nimblePath, projectRoot: string): ProjectManager =
  ## Create new project manager
  result = ProjectManager(
    nimblePath: nimblePath,
    projectRoot: projectRoot,
    cache: initTable[string, ProjectInfo](),
    lastUpdate: getTime()
  )

proc execNimble*(pm: ProjectManager, args: string, workingDir: string = ""): (string, int) =
  ## Execute nimble command
  let cmd = pm.nimblePath & " " & args
  let dir = if workingDir.len > 0: workingDir else: pm.projectRoot
  
  var oldDir = ""
  if dir != getCurrentDir():
    oldDir = getCurrentDir()
    setCurrentDir(dir)
  
  result = execCmdEx(cmd)
  
  if oldDir.len > 0:
    setCurrentDir(oldDir)

proc withProjectRoot*(pm: ProjectManager, projectRoot: string): ProjectManager =
  ## Create a new ProjectManager with different project root
  result = pm
  if projectRoot.len > 0:
    result.projectRoot = projectRoot

proc findProjectRoot*(startDir: string): string =
  ## Find project root by looking for .nimble file in the given directory only
  ## Does NOT search parent directories
  let dir = absolutePath(startDir)
  for file in walkDir(dir):
    if file.kind == pcFile and file.path.endsWith(".nimble"):
      return dir
  return ""  # Return empty string if no .nimble found

proc parseNimbleDump*(pm: ProjectManager): Option[ProjectInfo] =
  ## Parse nimble dump output
  let (output, exitCode) = pm.execNimble("dump --json")
  
  if exitCode != 0:
    return none(ProjectInfo)
  
  try:
    let json = parseJson(output)
    var info = ProjectInfo()
    
    if json.hasKey("name"):
      info.name = json["name"].getStr()
    if json.hasKey("version"):
      info.version = json["version"].getStr()
    if json.hasKey("author"):
      info.author = json["author"].getStr()
    if json.hasKey("desc"):
      info.description = json["desc"].getStr()
    if json.hasKey("license"):
      info.license = json["license"].getStr()
    if json.hasKey("srcDir"):
      info.srcDir = json["srcDir"].getStr()
    if json.hasKey("bin"):
      for b in json["bin"]:
        info.bin.add(b.getStr())
    
    if json.hasKey("requires"):
      for req in json["requires"]:
        if req.hasKey("name") and req.hasKey("str"):
          let dep = Dependency(
            name: req["name"].getStr(),
            version: req["str"].getStr(),
            description: "",
            resolvedTo: if req.hasKey("ver"): req["ver"]["ver"].getStr() else: ""
          )
          info.requires.add(dep)
    
    return some(info)
  except:
    stderr.writeLine("Error parsing nimble dump: " & getCurrentExceptionMsg())
    return none(ProjectInfo)

proc parseNimbleDeps*(pm: ProjectManager): seq[Dependency] =
  ## Parse nimble deps output
  let (output, exitCode) = pm.execNimble("deps --format:json")
  
  if exitCode != 0:
    return @[]
  
  try:
    let json = parseJson(output)
    
    proc parseDepNode(node: JsonNode): Dependency =
      result = Dependency()
      if node.hasKey("name"):
        result.name = node["name"].getStr()
      if node.hasKey("version"):
        result.version = node["version"].getStr()
      if node.hasKey("resolvedTo"):
        result.resolvedTo = node["resolvedTo"].getStr()
    
    proc collectDeps(node: JsonNode, isDirect: bool = true): seq[Dependency] =
      if node.kind == JArray:
        for item in node:
          var dep = parseDepNode(item)
          
          # Collect transitive dependencies
          if item.hasKey("dependencies"):
            let transitive = collectDeps(item["dependencies"], false)
            for t in transitive:
              dep.dependencies.add(t.name)
          
          result.add(dep)
    
    return collectDeps(json)
  except:
    stderr.writeLine("Error parsing nimble deps: " & getCurrentExceptionMsg())
    return @[]

proc getProjectInfo*(pm: var ProjectManager): Option[ProjectInfo] =
  ## Get project info, using cache if fresh
  let cacheKey = pm.projectRoot
  
  # Check cache (valid for 5 minutes)
  if pm.cache.hasKey(cacheKey):
    let elapsed = getTime() - pm.lastUpdate
    if elapsed.inMinutes < 5:
      return some(pm.cache[cacheKey])
  
  # Parse fresh data
  let info = pm.parseNimbleDump()
  if info.isSome:
    pm.cache[cacheKey] = info.get()
    pm.lastUpdate = getTime()
  
  return info

proc getDependencies*(pm: ProjectManager, directOnly: bool = false): seq[Dependency] =
  ## Get project dependencies
  let deps = parseNimbleDeps(pm)
  
  if directOnly:
    # Return only direct dependencies (those without transitive parents)
    var directDeps: seq[Dependency]
    for dep in deps:
      directDeps.add(dep)
    return directDeps
  
  return deps

proc getDependencyPath*(pm: ProjectManager, pkgName: string): string =
  ## Get path to installed dependency
  let (output, exitCode) = pm.execNimble("path " & pkgName)
  if exitCode == 0:
    return output.strip()
  return ""

proc isDependencyInstalled*(pm: ProjectManager, pkgName: string): bool =
  ## Check if a dependency is installed
  return getDependencyPath(pm, pkgName).len > 0

proc getInstalledPackages*(pm: ProjectManager): seq[tuple[name, path: string]] =
  ## Get list of all installed packages
  let pkgsDir = getHomeDir() / ".nimble" / "pkgs2"
  
  if not dirExists(pkgsDir):
    return @[]
  
  for dir in walkDir(pkgsDir):
    if dir.kind == pcDir:
      let name = extractFilename(dir.path)
      # Parse name-version-hash format
      let parts = name.split("-")
      if parts.len >= 2:
        result.add((parts[0], dir.path))
  
  return result
