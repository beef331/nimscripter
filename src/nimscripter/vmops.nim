## This module contains the a template to implement procedures similar to those that are normally in the `nimscript` module
import std/os
import nimscripter/expose

proc exec(s: string) =
  if execShellCmd(s) != 0:
    raise newException(OSError, s)

proc listFiles(dir: string): seq[string] =
  for kind, path in walkDir(dir):
    if kind == pcFile:
      result.add path

proc listDirs(dir: string): seq[string] =
  for kind, path in walkDir(dir):
    if kind == pcDir:
      result.add path

proc removeDir(dir: string) = os.removeDir(dir, true)
proc removeFile(dir: string) =
  try:
    os.removeFile(dir)
  except:
    discard

template addVmops*(module: untyped) =
  ## Adds the ops to the provided `module`
  ## this covers most of what the nimscript provides, and adds some more.
  exportTo(module,
    getCurrentDir,
    setCurrentDir,
    moveFile,
    moveDir,
    execShellCmd,
    exec,
    existsOrCreateDir,
    tryRemoveFile,
    listFiles,
    listDirs,
    vmops.removeDir,
    vmops.removeFile
  )