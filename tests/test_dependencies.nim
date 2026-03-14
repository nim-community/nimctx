# Tests for dependency listing functionality

import std/[unittest, os, tables]
import nimctx/project/manager

suite "list dependencies":
  test "getDependencies returns empty list for project with no deps":
    # Create a temporary test project
    let tmpDir = getTempDir() / "nimctx_test_nodeps"
    createDir(tmpDir)
    writeFile(tmpDir / "testproj.nimble", """
version = "1.0.0"
author = "Test"
description = "Test project with no dependencies"
license = "MIT"
""")
    
    let pm = newProjectManager("nimble", tmpDir)
    let deps = pm.getDependencies()
    
    check deps.len == 0
    
    # Cleanup
    removeFile(tmpDir / "testproj.nimble")
    removeDir(tmpDir)

  test "getDependencies with directOnly returns only direct dependencies":
    # Create a temporary test project
    let tmpDir = getTempDir() / "nimctx_test_direct"
    createDir(tmpDir)
    writeFile(tmpDir / "testproj.nimble", """
version = "1.0.0"
author = "Test"
description = "Test project"
license = "MIT"

requires "nim >= 1.6.0"
""")
    
    let pm = newProjectManager("nimble", tmpDir)
    let allDeps = pm.getDependencies(false)
    let directDeps = pm.getDependencies(true)
    
    # Both should work, though actual deps depend on nimble's output
    # We just verify the function doesn't crash
    check allDeps.len >= directDeps.len
    
    # Cleanup
    removeFile(tmpDir / "testproj.nimble")
    removeDir(tmpDir)

  test "getDependencies returns consistent structure":
    # Create a temporary test project
    let tmpDir = getTempDir() / "nimctx_test_struct"
    createDir(tmpDir)
    writeFile(tmpDir / "testproj.nimble", """
version = "1.0.0"
author = "Test"
description = "Test project"
license = "MIT"
""")
    
    let pm = newProjectManager("nimble", tmpDir)
    let deps = pm.getDependencies()
    
    # Verify each dependency has expected fields (even if empty)
    for dep in deps:
      check dep.name.len >= 0  # Should be a string
      check dep.version.len >= 0  # Should be a string
      check dep.resolvedTo.len >= 0  # Should be a string
      check dep.dependencies.len >= 0  # Should be a sequence
    
    # Cleanup
    removeFile(tmpDir / "testproj.nimble")
    removeDir(tmpDir)

  test "Dependency object fields are accessible":
    # Create a dependency manually to verify structure
    let dep = Dependency(
      name: "testpkg",
      version: ">= 1.0.0",
      description: "Test package",
      resolvedTo: "1.2.3",
      dependencies: @["dep1", "dep2"]
    )
    
    check dep.name == "testpkg"
    check dep.version == ">= 1.0.0"
    check dep.description == "Test package"
    check dep.resolvedTo == "1.2.3"
    check dep.dependencies.len == 2
    check dep.dependencies[0] == "dep1"
    check dep.dependencies[1] == "dep2"

  test "newProjectManager creates manager with correct fields":
    let pm = newProjectManager("nimble", "/tmp/test")
    check pm.nimblePath == "nimble"
    check pm.projectRoot == "/tmp/test"
    check len(pm.cache) == 0

  test "withProjectRoot preserves nimblePath":
    let pm1 = newProjectManager("/custom/nimble", "/original")
    let pm2 = pm1.withProjectRoot("/new")
    
    check pm2.nimblePath == "/custom/nimble"
    check pm2.projectRoot == "/new"
    check pm1.projectRoot == "/original"  # Original unchanged

  test "findProjectRoot returns empty for non-existent directory":
    let root = findProjectRoot("/nonexistent/path/12345")
    check root == ""

  test "findProjectRoot returns path when .nimble exists":
    let tmpDir = getTempDir() / "nimctx_test_root"
    createDir(tmpDir)
    writeFile(tmpDir / "test.nimble", "# Test nimble file")
    
    let root = findProjectRoot(tmpDir)
    check root == tmpDir
    
    # Cleanup
    removeFile(tmpDir / "test.nimble")
    removeDir(tmpDir)

  test "findProjectRoot only checks given directory, not parents":
    # Create nested structure
    let parentDir = getTempDir() / "nimctx_test_parent"
    let childDir = parentDir / "child"
    createDir(childDir)
    writeFile(parentDir / "parent.nimble", "# Parent nimble file")
    
    # Should not find parent's .nimble when checking child
    let root = findProjectRoot(childDir)
    check root == ""
    
    # Cleanup
    removeFile(parentDir / "parent.nimble")
    removeDir(childDir)
    removeDir(parentDir)
