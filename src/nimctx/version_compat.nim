# Version compatibility checker for Nim projects
# Tests code against multiple Nim versions using choosenim

import std/[os, osproc, strutils, sequtils, re, strformat, options, algorithm]

type
  NimVersion* = object
    version*: string      # e.g., "2.0.2", "#devel"
    isDevel*: bool
    isChannel*: bool      # stable, devel, etc.
  
  CompileResult* = object
    version*: string
    success*: bool
    output*: string
    errors*: seq[string]
    warnings*: seq[string]
    hints*: seq[string]
  
  CompatReport* = object
    projectPath*: string
    testFile*: string
    results*: seq[CompileResult]
    compatibleVersions*: seq[string]
    incompatibleVersions*: seq[string]
    minCompatibleVersion*: Option[string]
    maxCompatibleVersion*: Option[string]
    suggestedNimbleRequires*: string

proc findNimbleFiles*(dir: string): seq[string] =
  ## Find all .nimble files in a directory
  result = @[]
  if not dirExists(dir):
    return result
  
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nimble"):
      result.add(path)

proc getInstalledVersions*(): seq[NimVersion] =
  ## Get all installed Nim versions from choosenim
  result = @[]
  
  let (output, exitCode) = execCmdEx("choosenim versions --installed")
  if exitCode != 0:
    return result
  
  # Parse output like "2.2.4", "2.0.2", "#devel"
  for line in output.splitLines:
    let trimmed = line.strip()
    # Skip empty lines and headers (check both raw and ANSI-stripped)
    var cleanLine = trimmed.replace(re"\x1B\[[0-9;]*[a-zA-Z]", "")
    cleanLine = cleanLine.strip()
    
    if cleanLine.len == 0: continue
    if cleanLine.startsWith("Channel:"): continue
    if cleanLine.startsWith("Installed:"): continue
    if "update available" in cleanLine.toLowerAscii(): continue
    
    # Remove "* " prefix (current version indicator)
    var versionStr = cleanLine.replace("* ", "").strip()
    
    # Skip if doesn't look like a version (should start with digit or #)
    if versionStr.len == 0: continue
    if not (versionStr[0] in {'0'..'9'} or versionStr[0] == '#'):
      continue
    
    # Skip channel names without version numbers
    if versionStr in ["stable", "devel", "lts"]:
      continue
    
    var ver = NimVersion(
      version: versionStr,
      isDevel: versionStr == "#devel",
      isChannel: versionStr in ["stable", "devel", "lts"]
    )
    result.add(ver)

proc switchVersion*(version: string): bool =
  ## Switch to a specific Nim version using choosenim
  # Handle versions with # (like #devel) by quoting properly
  let quotedVersion = if version.startsWith("#"): "\"" & version & "\"" else: version
  let cmd = "choosenim " & quotedVersion
  let (output, exitCode) = execCmdEx(cmd, options = {poStdErrToStdOut})
  return exitCode == 0

proc parseCompileOutput*(output: string): tuple[errors, warnings, hints: seq[string]] =
  ## Parse nim check output into errors, warnings, and hints
  var errors: seq[string] = @[]
  var warnings: seq[string] = @[]
  var hints: seq[string] = @[]
  
  for line in output.splitLines:
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    
    # Error patterns
    if "Error:" in trimmed or "template/generic instantiation" in trimmed:
      errors.add(trimmed)
    elif "Warning:" in trimmed:
      warnings.add(trimmed)
    elif "Hint:" in trimmed and "SuccessX" notin trimmed:
      hints.add(trimmed)
  
  return (errors, warnings, hints)

proc testCompile*(filePath: string, nimVersion: string): CompileResult =
  ## Test if a file compiles with a specific Nim version
  result = CompileResult(version: nimVersion)
  
  # First switch to the target version
  if not switchVersion(nimVersion):
    result.success = false
    result.output = "Failed to switch to Nim version: " & nimVersion
    result.errors.add(result.output)
    return result
  
  # Run nim check
  let cmd = "nim check " & quoteShell(filePath)
  let (output, exitCode) = execCmdEx(cmd, options = {poStdErrToStdOut})
  
  result.output = output
  let (errors, warnings, hints) = parseCompileOutput(output)
  result.errors = errors
  result.warnings = warnings
  result.hints = hints
  
  # Success if no errors (warnings and hints are OK)
  result.success = errors.len == 0

proc compareVersions*(a, b: string): int =
  ## Compare two version strings (e.g., "2.0.2" vs "2.0.8")
  ## Returns: -1 if a < b, 0 if a == b, 1 if a > b
  
  # Handle special cases
  if a == b:
    return 0
  if a == "#devel" or a == "devel":
    return 1  # devel is always latest
  if b == "#devel" or b == "devel":
    return -1
  
  let partsA = a.split('.')
  let partsB = b.split('.')
  
  for i in 0 ..< max(partsA.len, partsB.len):
    let numA = if i < partsA.len: parseInt(partsA[i]) else: 0
    let numB = if i < partsB.len: parseInt(partsB[i]) else: 0
    
    if numA < numB:
      return -1
    elif numA > numB:
      return 1
  
  return 0

proc checkVersionCompat*(
  filePath: string,
  versions: seq[string] = @[],
  testAllInstalled: bool = true
): CompatReport =
  ## Check code compatibility with multiple Nim versions
  
  result = CompatReport(
    projectPath: filePath.parentDir(),
    testFile: filePath
  )
  
  var versionsToTest: seq[string]
  
  if testAllInstalled:
    # Get all installed versions
    let installed = getInstalledVersions()
    versionsToTest = installed.mapIt(it.version)
  else:
    versionsToTest = versions
  
  # Sort versions for better reporting
  versionsToTest.sort(proc(a, b: string): int = compareVersions(a, b))
  
  # Remember current version to restore later
  let (currentVersionOutput, _) = execCmdEx("nim --version")
  var currentVersion = ""
  for line in currentVersionOutput.splitLines:
    if line.startsWith("Nim Compiler Version"):
      let parts = line.split()
      if parts.len >= 4:
        currentVersion = parts[^1]  # Get version number
      break
  
  # Test each version
  for version in versionsToTest:
    let compileResult = testCompile(filePath, version)
    result.results.add(compileResult)
    
    if compileResult.success:
      result.compatibleVersions.add(version)
    else:
      result.incompatibleVersions.add(version)
  
  # Restore original version
  if currentVersion.len > 0:
    discard switchVersion(currentVersion)
  
  # Determine min/max compatible versions
  if result.compatibleVersions.len > 0:
    result.minCompatibleVersion = some(result.compatibleVersions[0])
    result.maxCompatibleVersion = some(result.compatibleVersions[^1])
    
    # Generate suggested nimble requires
    result.suggestedNimbleRequires = "requires \"nim >= " & result.compatibleVersions[0] & "\""

proc parseNimbleFile*(nimblePath: string): tuple[content: string, nimRequires: seq[string], otherRequires: seq[string]] =
  ## Parse a nimble file and extract requires statements
  result.content = readFile(nimblePath)
  result.nimRequires = @[]
  result.otherRequires = @[]
  
  for line in result.content.splitLines:
    let trimmed = line.strip()
    if trimmed.toLowerAscii().startsWith("requires") and "nim" in trimmed.toLowerAscii():
      result.nimRequires.add(line)
    elif trimmed.toLowerAscii().startsWith("requires"):
      result.otherRequires.add(line)

proc updateNimbleRequires*(nimblePath: string, newNimRequires: string): bool =
  ## Update the Nim version requirement in nimble file
  let (content, nimRequires, otherRequires) = parseNimbleFile(nimblePath)
  
  if nimRequires.len == 0:
    # No existing nim requires, add one after the last requires
    var lines = content.splitLines()
    var lastRequiresIdx = -1
    
    for i, line in lines:
      if line.strip().toLowerAscii().startsWith("requires"):
        lastRequiresIdx = i
    
    if lastRequiresIdx >= 0:
      lines.insert(newNimRequires, lastRequiresIdx + 1)
    else:
      # No requires at all, add at end
      lines.add(newNimRequires)
    
    writeFile(nimblePath, lines.join("\n"))
    return true
  else:
    # Replace existing nim requires
    var newContent = content
    for oldReq in nimRequires:
      newContent = newContent.replace(oldReq, newNimRequires)
    
    writeFile(nimblePath, newContent)
    return true

proc generateCompatReportMarkdown*(report: CompatReport): string =
  ## Generate a markdown formatted compatibility report
  result = "## Nim Version Compatibility Report\n\n"
  
  result.add(fmt"**Tested File:** `{report.testFile}`\n\n")
  
  # Highlight minimum compatible version (most important!)
  if report.minCompatibleVersion.isSome:
    let minVer = report.minCompatibleVersion.get
    result.add("### 🎯 Minimum Supported Version\n\n")
    result.add(fmt"**`{minVer}`**\n\n")
    result.add(fmt"Your code requires Nim **{minVer}** or later.\n\n")
    
    # Add compatibility range info
    if report.maxCompatibleVersion.isSome:
      let maxVer = report.maxCompatibleVersion.get
      if minVer != maxVer:
        result.add(fmt"✅ Compatible range: `{minVer}` to `{maxVer}`\n\n")
      else:
        result.add(fmt"⚠️ Only tested with: `{minVer}`\n\n")
  
  # Summary table
  result.add("### Test Results\n\n")
  result.add("| Version | Status | Errors | Warnings |\n")
  result.add("|---------|--------|--------|----------|\n")
  
  for res in report.results:
    let status = if res.success: "✅ Pass" else: "❌ Fail"
    let errorCount = res.errors.len
    let warningCount = res.warnings.len
    result.add(fmt"| {res.version} | {status} | {errorCount} | {warningCount} |\n")
  
  result.add("\n")
  
  # Compatible versions list
  if report.compatibleVersions.len > 0:
    result.add("### ✅ All Compatible Versions\n\n")
    result.add("```\n")
    result.add(report.compatibleVersions.join(", "))
    result.add("\n```\n\n")
  
  # Incompatible versions
  if report.incompatibleVersions.len > 0:
    result.add("### ❌ Incompatible Versions\n\n")
    result.add("```\n")
    result.add(report.incompatibleVersions.join(", "))
    result.add("\n```\n\n")
  
  # Suggested nimble requires
  if report.suggestedNimbleRequires.len > 0:
    result.add("### 💡 Suggested nimble.nimble change\n\n")
    result.add("Based on compatibility testing, update your nimble file with this line:\n\n")
    result.add("```nim\n")
    result.add(report.suggestedNimbleRequires)
    result.add("\n```\n\n")
    result.add("This only modifies the Nim compiler version requirement. Other dependencies (libraries) are not changed.\n\n")
  
  # Detailed error info for incompatible versions
  var hasErrorDetails = false
  for res in report.results:
    if not res.success and res.errors.len > 0:
      if not hasErrorDetails:
        result.add("### Error Details\n\n")
        hasErrorDetails = true
      result.add(fmt"**{res.version}:**\n\n")
      result.add("```\n")
      for err in res.errors[0 ..< min(5, res.errors.len)]:
        result.add(err & "\n")
      if res.errors.len > 5:
        result.add(fmt"... and {res.errors.len - 5} more errors\n")
      result.add("```\n\n")

when isMainModule:
  # Test
  echo "Installed versions:"
  for ver in getInstalledVersions():
    echo "  - ", ver.version
