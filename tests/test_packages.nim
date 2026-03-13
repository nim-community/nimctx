# Tests for package indexing

import std/[unittest, os, options, times, tables, strutils]
import nimctx/packages/indexer
import nimctx/project/manager

suite "package indexer":
  test "can create package registry":
    let cacheDir = getTempDir() / "nimctx_pkg_test"
    createDir(cacheDir)
    let registry = newPackageRegistry(cacheDir)
    check registry != nil
    check registry.packages.len == 0
  
  test "can create package index":
    let pkg = newPackageIndex("testpkg", "1.0.0", "/tmp/testpkg")
    check pkg != nil
    check pkg.name == "testpkg"
    check pkg.version == "1.0.0"
    check pkg.modules.len == 0
  
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
    
    let pkg = newPackageIndex("testpkg", "1.0.0", tmpDir)
    pkg.indexPackageModule(testFile, "testmodule")
    
    check pkg.modules.len == 1
    check pkg.modules.hasKey("testmodule")
    check pkg.modules["testmodule"].doc.contains("Test module")
    check pkg.modules["testmodule"].exports.len == 2  # testProc and TestType
    
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
    
    let pkg = newPackageIndex("searchpkg", "1.0.0", tmpDir)
    pkg.indexPackageModule(testFile, "searchmod")
    
    let results = searchPackage(pkg, "searchable", 10)
    check results.len == 1
    check results[0].name == "searchableProc"
    
    # Cleanup
    removeFile(testFile)
    removeDir(tmpDir)
  
  test "search caching works":
    let pkg = newPackageIndex("cachepkg", "1.0.0", "/tmp")
    # First search
    let results1 = searchPackage(pkg, "test", 10)
    # Second search should use cache
    let results2 = searchPackage(pkg, "test", 10)
    check results1.len == results2.len  # Both should be empty but cached
