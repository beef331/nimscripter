## This module contains the a template to implement procedures similar to those that are normally in the `nimscript` module
import std/[os, osproc]
import nimscripter/expose

proc exec(s: string) =
  if execShellCmd(s) != 0:
    raise newException(OSError, s)

proc gorgeEx(cmd: string): tuple[output: string, exitCode: int] =
  execCmdEx(cmd)

proc listFiles(dir: string): seq[string] =
  for kind, path in walkDir(dir):
    if kind == pcFile:
      result.add path

proc listDirs(dir: string): seq[string] =
  for kind, path in walkDir(dir):
    if kind == pcDir:
      result.add path

proc rmDir(dir: string, checkDir = false) = removeDir(dir, checkDir)
proc rmFile(dir: string) = removeFile(dir)
proc mvDir(`from`, to: string, checkDir = false) = moveDir(`from`, to)
proc mvFile(`from`, to: string) = moveFile(`from`, to)
proc cd(dir: string) = setCurrentDir(dir)


template addVmops*(module: untyped) =
  ## Adds the ops to the provided `module`
  ## this covers most of what the nimscript provides, and adds some more.
  exportTo(module,
    getCurrentDir,
    setCurrentDir,
    cd,
    mvDir,
    mvFile,
    execShellCmd,
    exec,
    existsOrCreateDir,
    tryRemoveFile,
    listFiles,
    listDirs,
    rmDir,
    rmFile,
    vmops.gorgeEx
  )
