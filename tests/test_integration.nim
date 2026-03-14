# Integration tests using nimctx itself as the test project

import std/[unittest, os, strutils, json, options, tables]
import nimctx/[config, stdlib/indexer, project/manager, packages/indexer]

const projectRoot = currentSourcePath().parentDir().parentDir()

suite "integration tests with nimctx project":
  
  test "can find project root with nimble file":
    let root = findProjectRoot(projectRoot)
    check root == projectRoot
    check fileExists(root / "nimctx.nimble")

  test "can create project manager for nimctx":
    let pm = newProjectManager("nimble", projectRoot)
    check pm.projectRoot == projectRoot
    check pm.nimblePath == "nimble"

  test "can list nimctx dependencies (if any)":
    let pm = newProjectManager("nimble", projectRoot)
    let deps = pm.getDependencies(true)
    
    # Note: In CI/test environment, nimble deps might return empty
    # This test documents the behavior
    echo "Found " & $deps.len & " dependencies"
    for dep in deps:
      echo "  - " & dep.name & " " & dep.version
    
    # If we have deps, check for expected ones
    if deps.len > 0:
      var hasNimcp = false
      for dep in deps:
        if dep.name == "nimcp":
          hasNimcp = true
          break
      check hasNimcp

  test "can index nimctx dependencies (if any)":
    let cacheDir = getTempDir() / "nimctx_integration_test"
    createDir(cacheDir)
    
    let pm = newProjectManager("nimble", projectRoot)
    let registry = newPackageRegistry(cacheDir / "packages", "nim")
    
    # Index dependencies
    let deps = pm.getDependencies(true)
    var indexedCount = 0
    for dep in deps:
      if not registry.packages.hasKey(dep.name):
        let pkgPath = pm.getDependencyPath(dep.name)
        if pkgPath.len > 0:
          discard registry.indexPackage(dep.name, pkgPath)
          indexedCount.inc()
    
    echo "Indexed " & $indexedCount & " packages"
    
    # If we had deps, we should have indexed something
    if deps.len > 0:
      check indexedCount > 0
      check registry.packages.len > 0

  test "can resolve imports for nimctx dependencies":
    let pm = newProjectManager("nimble", projectRoot)
    
    # Try to resolve a known dependency import
    let nimcpPath = pm.getDependencyPath("nimcp")
    if nimcpPath.len > 0:
      echo "Found nimcp at: " & nimcpPath
      check dirExists(nimcpPath)
    else:
      echo "nimcp not found (may not be installed in test environment)"

  test "withProjectRoot works with nimctx project":
    let pm1 = newProjectManager("nimble", "/some/other/path")
    let pm2 = pm1.withProjectRoot(projectRoot)
    
    check pm1.projectRoot == "/some/other/path"  # Original unchanged
    check pm2.projectRoot == projectRoot  # New has nimctx root
    
    # Can get dependencies from nimctx (may be empty in test env)
    let deps = pm2.getDependencies(true)
    echo "Dependencies from nimctx project: " & $deps.len

  test "can read nimctx nimble file":
    let pm = newProjectManager("nimble", projectRoot)
    let info = pm.parseNimbleDump()
    
    if info.isSome:
      let i = info.get()
      check i.name == "nimctx"
      check i.version == "0.1.0"
      check i.srcDir == "src"
      echo "Package: " & i.name & " v" & i.version
    else:
      echo "Could not parse nimble dump (nimble may not be available)"
