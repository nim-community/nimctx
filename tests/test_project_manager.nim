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
