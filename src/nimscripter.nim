import compiler / [nimeval, renderer, ast, llstream, vmdef, vm, lineinfos]
import std/[os, json, options, importutils]
export destroyInterpreter, options, Interpreter, importutils

import nimscripter/procsignature

type
  VMQuit* = object of CatchableError
    info*: TLineInfo

proc getSearchPath(path: string): seq[string] =
  result.add path
  for dir in walkDirRec(path, {pcDir}):
    result.add dir

proc loadScript*(
  script: string,
  userProcs: openArray[VmProcSignature],
  isFile = true,
  modules: varargs[string],
  stdPath = "./stdlib"): Option[Interpreter] =

  if not isFile or fileExists(script):
    var additions = ""
    for `mod` in modules: # Add modules
      additions.insert("import " & `mod` & "\n", 0)

    for uProc in userProcs:
      additions.add uProc.vmRunImpl

    var searchPaths = getSearchPath(stdPath)
    let scriptName = if isFile: script.splitFile.name else: "script"

    if isFile: # If is file we want to enable relative imports
      searchPaths.add script.parentDir

    let
      intr = createInterpreter(scriptName, searchPaths)
      script = if isFile: readFile(script) else: script

    for uProc in userProcs:
      intr.implementRoutine("*", scriptName, uProc.name, uProc.vmProc)

    when defined(debugScript): writeFile("debugScript.nims", additions & script)

    intr.evalScript(llStreamOpen(additions & script))
    result = option(intr)

proc loadScript*(
  script: string,
  isFile = true,
  modules: varargs[string],
  stdPath = "./stdlib"): Option[Interpreter] {.inline.} =
  loadScript(script, [], isFile, modules, stdPath)


proc invoke*(intr: Interpreter, procName: string, argBuffer: string = "", T: typeDesc = void): T =
  let
    foreignProc = intr.selectRoutine(procName & "Exported")
  var ret: PNode
  if argBuffer.len > 0:
    ret = intr.callRoutine(foreignProc, [newStrNode(nkStrLit, argBuffer)])
  else:
    ret = intr.callRoutine(foreignProc, [])
  when T isnot void:
    var pos: BiggestInt
