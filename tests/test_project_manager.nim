# Tests for project manager

import std/[unittest, os, strutils]
import nimctx/project/manager

suite "project manager":
  test "can create project manager":
    let pm = newProjectManager("nimble", "/tmp")
    check pm.nimblePath == "nimble"
    check pm.projectRoot == "/tmp"

  test "findProjectRoot finds .nimble file in directory":
    # Create temp directory with .nimble file
    let tmpDir = getTempDir() / "nimctx_test_project"
    createDir(tmpDir)
    writeFile(tmpDir / "test.nimble", "# Test nimble file")
    
    let root = findProjectRoot(tmpDir)
    check root == tmpDir
    
    # Cleanup
    removeFile(tmpDir / "test.nimble")
    removeDir(tmpDir)

  test "findProjectRoot returns empty when no .nimble":
    let tmpDir = getTempDir() / "nimctx_test_no_nimble"
    createDir(tmpDir)
    
    let root = findProjectRoot(tmpDir)
    check root == ""
    
    # Cleanup
    removeDir(tmpDir)

  test "withProjectRoot creates new manager with different root":
    let pm1 = newProjectManager("nimble", "/original")
    let pm2 = pm1.withProjectRoot("/new/root")
    
    check pm1.projectRoot == "/original"  # Original unchanged
    check pm2.projectRoot == "/new/root"  # New has different root
    check pm2.nimblePath == pm1.nimblePath  # Other fields copied

  test "withProjectRoot keeps original when empty string":
    let pm1 = newProjectManager("nimble", "/original")
    let pm2 = pm1.withProjectRoot("")
    
    check pm2.projectRoot == "/original"

  test "getDependencyPath falls back to nimbledeps/pkgs2":
    let tmpDir = getTempDir() / "nimctx_test_deps_pkgs2"
    let pkgDir = tmpDir / "nimbledeps" / "pkgs2" / "mypkg-1.0.0-abc123"
    createDir(pkgDir)
    
    let pm = newProjectManager("nimble", tmpDir)
    let path = pm.getDependencyPath("mypkg")
    check path == pkgDir
    
    removeDir(tmpDir)

  test "getDependencyPath returns empty when not found":
    let tmpDir = getTempDir() / "nimctx_test_deps_missing"
    createDir(tmpDir)
    
    let pm = newProjectManager("nimble", tmpDir)
    let path = pm.getDependencyPath("nonexistent")
    check path == ""
    
    removeDir(tmpDir)

  test "isDependencyInstalled uses nimbledeps fallback":
    let tmpDir = getTempDir() / "nimctx_test_installed"
    let pkgDir = tmpDir / "nimbledeps" / "pkgs2" / "testpkg-1.0.0"
    createDir(pkgDir)
    
    let pm = newProjectManager("nimble", tmpDir)
    check pm.isDependencyInstalled("testpkg") == true
    check pm.isDependencyInstalled("missing") == false
    
    removeDir(tmpDir)
