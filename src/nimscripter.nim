import compiler / [nimeval, renderer, ast, llstream, vmdef, vm, lineinfos, idents]
import std/[os, json, options, strutils, macros]
import nimscripter/expose
export destroyInterpreter, options, Interpreter, ast, lineinfos, idents

import nimscripter/procsignature

type
  VMQuit* = object of CatchableError
    info*: TLineInfo
  VmProcNotFound* = object of CatchableError

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


macro invoke*(intr: Interpreter, pName: untyped, args: varargs[typed],
    returnType: typedesc = void): untyped =
  let
    convs = newStmtList()
    procName = newLit($pname)
    argSym = genSym(nskVar, "args")
    retName = genSym(nskLet, "ret")
    retNode = newStmtList()
    resultIdnt = ident"res"

  if not returnType.eqIdent("void"):
    retNode.add nnkAsgn.newTree(resultIdnt, newCall(ident"fromVm", returnType, retName))
    retNode.add resultIdnt

  for x in args:
    convs.add newCall(ident"add", argSym, newCall(ident"toVm", x))
  result = quote do:
    block:
      when `returnType` isnot void:
        var `resultIdnt`: `returnType`
      let nsProc = `intr`.selectRoutine(`procName`)
      if nsProc != nil:
        var `argSym`: seq[Pnode]
        `convs`
        let `retName` = `intr`.callRoutine(nsProc, `argSym`)
        `retNode`
      else:
        raise newException(VmProcNotFound, "'$#' was not found in the script." % `procName`)
