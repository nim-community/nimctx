# Tests for package indexing

import std/[unittest, os, options, strutils, json, tables]
import nimctx/packages/indexer
import nimctx/utils/indexing

suite "package indexer":
  test "can create package registry":
    let cacheDir = getTempDir() / "nimctx_pkg_test"
    createDir(cacheDir)
    let registry = newPackageRegistry(cacheDir, "nim")
    check registry != nil
    check registry.packages.len == 0
  
  test "can create package index":
    let cacheDir = getTempDir() / "nimctx_pkg_test2"
    let pkg = newPackageIndex("testpkg", "1.0.0", "/tmp/testpkg", cacheDir, "nim")
    check pkg != nil
  
  test "can index package module":
    # Create a temporary test file
    let tmpDir = getTempDir() / "nimctx_test_pkg"
    createDir(tmpDir)
    let testFile = tmpDir / "testmodule.nim"
    writeFile(testFile, """
## Test module documentation
## Multi-line doc

proc testProc*(x: int): int =
  ## Test procedure
  x + 1

type TestType* = object
  ## Test type
  field: int
""")
    
    let cacheDir = getTempDir() / "nimctx_pkg_test3"
    let pkg = newPackageIndex("testpkg", "1.0.0", tmpDir, cacheDir, "nim")
    
    # Generate JSON doc using nim
    discard indexSingleModule("nim", testFile)
    
    # Parse JSON and add to SQLite
    let jsonPath = testFile.parentDir() / "htmldocs" / "testmodule.json"
    if fileExists(jsonPath):
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
          
          pkg.addSymbol(symName, symKind, testFile, symCode, symDesc, symLine, symCol, "testpkg")
    
    # Verify symbols were added
    let symbols = pkg.getModuleSymbols("testmodule")
    check symbols.len == 2  # testProc and TestType
    
    # Cleanup
    removeFile(testFile)
    removeDir(tmpDir)
  
  test "can search in package":
    let tmpDir = getTempDir() / "nimctx_test_pkg2"
    createDir(tmpDir)
    let testFile = tmpDir / "searchmod.nim"
    writeFile(testFile, """
proc searchableProc*(x: int): int =
  ## A searchable procedure
  x * 2
""")
    
    let cacheDir = getTempDir() / "nimctx_pkg_test4"
    let pkg = newPackageIndex("searchpkg", "1.0.0", tmpDir, cacheDir, "nim")
    
    # Generate JSON doc
    discard indexSingleModule("nim", testFile)
    
    # Parse and add to SQLite
    let jsonPath = testFile.parentDir() / "htmldocs" / "searchmod.json"
    if fileExists(jsonPath):
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
          
          pkg.addSymbol(symName, symKind, testFile, symCode, symDesc, symLine, symCol, "searchpkg")
    
    let results = searchPackage(pkg, "searchable", 10)
    check results.len == 1
    check results[0].name == "searchableProc"
    
    # Cleanup
    removeFile(testFile)
    removeDir(tmpDir)
  
  test "search caching works":
    let cacheDir = getTempDir() / "nimctx_pkg_test5"
    let pkg = newPackageIndex("cachepkg", "1.0.0", "/tmp", cacheDir, "nim")
    # First search
    let results1 = searchPackage(pkg, "test", 10)
    # Second search should use cache
    let results2 = searchPackage(pkg, "test", 10)
    check results1.len == results2.len  # Both should be empty but cached
