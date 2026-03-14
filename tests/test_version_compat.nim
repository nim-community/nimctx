# Tests for version compatibility checker

import std/[unittest, os, strutils, options]
import nimctx/version_compat

suite "version comparison":
  test "compareVersions handles equal versions":
    check compareVersions("1.0.0", "1.0.0") == 0
    check compareVersions("2.2.0", "2.2.0") == 0

  test "compareVersions handles different versions":
    check compareVersions("1.0.0", "2.0.0") == -1
    check compareVersions("2.0.0", "1.0.0") == 1
    check compareVersions("1.6.0", "1.6.10") == -1
    check compareVersions("2.0.0", "1.6.14") == 1

  test "compareVersions handles devel as latest":
    check compareVersions("#devel", "1.0.0") == 1
    check compareVersions("1.0.0", "#devel") == -1
    check compareVersions("#devel", "#devel") == 0
    check compareVersions("#devel", "99.99.99") == 1

  test "compareVersions handles different length versions":
    check compareVersions("1.0", "1.0.0") == 0
    check compareVersions("1", "1.0.0") == 0
    check compareVersions("1.6", "1.6.14") == -1

  test "compareVersions handles string devel":
    check compareVersions("devel", "1.0.0") == 1
    check compareVersions("1.0.0", "devel") == -1

suite "compile output parsing":
  test "parseCompileOutput extracts errors":
    let output = """
src/test.nim(10, 5) Error: undeclared identifier: 'foo'
src/test.nim(15, 10) Error: type mismatch
"""
    let (errors, warnings, hints) = parseCompileOutput(output)
    check errors.len == 2
    check "undeclared identifier" in errors[0]
    check "type mismatch" in errors[1]
    check warnings.len == 0

  test "parseCompileOutput extracts warnings":
    let output = """
src/test.nim(5, 3) Warning: deprecated
some other text
src/test.nim(8, 1) Warning: unused import
"""
    let (errors, warnings, hints) = parseCompileOutput(output)
    check errors.len == 0
    check warnings.len == 2
    check "deprecated" in warnings[0]

  test "parseCompileOutput extracts hints":
    let output = """
src/test.nim(1, 1) Hint: used config file
src/test.nim(5, 1) Hint: 'foo' is declared but not used
"""
    let (errors, warnings, hints) = parseCompileOutput(output)
    check hints.len == 2
    check "declared but not used" in hints[1]

  test "parseCompileOutput ignores SuccessX":
    let output = """
Hint: mm: orc; threads: on; [SuccessX]
"""
    let (errors, warnings, hints) = parseCompileOutput(output)
    check hints.len == 0

  test "parseCompileOutput handles mixed output":
    let output = """
src/test.nim(1, 1) Hint: used config file
src/test.nim(10, 5) Warning: deprecated
src/test.nim(20, 3) Error: undefined symbol
Hint: mm: orc [SuccessX]
"""
    let (errors, warnings, hints) = parseCompileOutput(output)
    check errors.len == 1
    check warnings.len == 1
    check hints.len == 1

suite "nimble file operations":
  test "findNimbleFiles finds .nimble files":
    let tmpDir = getTempDir() / "nimctx_test_nimble"
    createDir(tmpDir)
    writeFile(tmpDir / "test.nimble", "# Test nimble file")
    
    let files = findNimbleFiles(tmpDir)
    check files.len == 1
    check files[0].endsWith("test.nimble")
    
    # Cleanup
    removeFile(tmpDir / "test.nimble")
    removeDir(tmpDir)

  test "findNimbleFiles returns empty for non-existent dir":
    let files = findNimbleFiles("/nonexistent/path/12345")
    check files.len == 0

  test "findNimbleFiles ignores non-.nimble files":
    let tmpDir = getTempDir() / "nimctx_test_nimble2"
    createDir(tmpDir)
    writeFile(tmpDir / "test.txt", "not a nimble file")
    writeFile(tmpDir / "test.nim", "not a nimble file either")
    
    let files = findNimbleFiles(tmpDir)
    check files.len == 0
    
    # Cleanup
    removeFile(tmpDir / "test.txt")
    removeFile(tmpDir / "test.nim")
    removeDir(tmpDir)

  test "parseNimbleFile extracts requires":
    let tmpDir = getTempDir() / "nimctx_test_parse"
    createDir(tmpDir)
    let nimbleContent = """
version = "1.0.0"
author = "Test"
description = "Test package"
license = "MIT"

requires "nim >= 1.6.0"
requires "jsony >= 1.0.0"
"""
    writeFile(tmpDir / "test.nimble", nimbleContent)
    
    let (content, nimRequires, otherRequires) = parseNimbleFile(tmpDir / "test.nimble")
    check "nim >= 1.6.0" in nimRequires.join()
    check "jsony >= 1.0.0" in otherRequires.join()
    
    # Cleanup
    removeFile(tmpDir / "test.nimble")
    removeDir(tmpDir)

  test "updateNimbleRequires updates existing nim requirement":
    let tmpDir = getTempDir() / "nimctx_test_update"
    createDir(tmpDir)
    let nimbleContent = """
version = "1.0.0"
requires "nim >= 1.4.0"
requires "jsony >= 1.0.0"
"""
    writeFile(tmpDir / "test.nimble", nimbleContent)
    
    let success = updateNimbleRequires(tmpDir / "test.nimble", "requires \"nim >= 2.0.0\"")
    check success == true
    
    let updated = readFile(tmpDir / "test.nimble")
    check "nim >= 2.0.0" in updated
    check "nim >= 1.4.0" notin updated
    check "jsony >= 1.0.0" in updated
    
    # Cleanup
    removeFile(tmpDir / "test.nimble")
    removeDir(tmpDir)

  test "updateNimbleRequires adds new requirement if none exists":
    let tmpDir = getTempDir() / "nimctx_test_add"
    createDir(tmpDir)
    let nimbleContent = """
version = "1.0.0"
requires "jsony >= 1.0.0"
"""
    writeFile(tmpDir / "test.nimble", nimbleContent)
    
    let success = updateNimbleRequires(tmpDir / "test.nimble", "requires \"nim >= 1.6.0\"")
    check success == true
    
    let updated = readFile(tmpDir / "test.nimble")
    check "nim >= 1.6.0" in updated
    
    # Cleanup
    removeFile(tmpDir / "test.nimble")
    removeDir(tmpDir)

suite "compat report generation":
  test "generateCompatReportMarkdown includes version info":
    var report = CompatReport(
      testFile: "/test/project.nim",
      compatibleVersions: @["1.6.14", "2.0.0"],
      incompatibleVersions: @["1.4.8"],
      minCompatibleVersion: some("1.6.14"),
      maxCompatibleVersion: some("2.0.0"),
      suggestedNimbleRequires: "requires \"nim >= 1.6.14\""
    )
    
    let md = generateCompatReportMarkdown(report)
    check "1.6.14" in md
    check "2.0.0" in md
    check "project.nim" in md
    check "requires" in md
