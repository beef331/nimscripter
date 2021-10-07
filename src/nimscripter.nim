import compiler / [nimeval, renderer, ast, llstream, vmdef, vm, lineinfos, idents]
import std/[os, json, options, strutils, macros]
import nimscripter/[expose, vmconversion]
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

proc errorHook(config, info, msg, severity: auto) {.gcsafe.} =
  if severity == Error and config.error_counter >= config.error_max:
    echo "Script Error: ", info, " ", msg
    raise (ref VMQuit)(info: info, msg: msg)

proc loadScript*(
  script: string,
  userProcs: openArray[VmProcSignature],
  isFile = true,
  additions = "",
  modules: varargs[string],
  stdPath = "./stdlib"): Option[Interpreter] =

  if not isFile or fileExists(script):
    var additions = additions
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
    intr.registerErrorHook(errorHook)
    try:
      intr.evalScript(llStreamOpen(additions & script))
      result = option(intr)
    except: discard

proc loadScript*(
  script: string,
  isFile = true,
  modules: varargs[string],
  stdPath = "./stdlib"): Option[Interpreter] {.inline.} =
  loadScript(script, [], isFile, modules = modules, stdPath = stdPath)


macro invoke*(intr: Interpreter, pName: untyped, args: varargs[typed],
    returnType: typedesc = void): untyped =
  let
    convs = newStmtList()
    procName = newLit($pname)
    argSym = genSym(nskVar, "args")
    retName = genSym(nskLet, "ret")
    retNode = newStmtList()
    resultIdnt = ident"res"
    fromVm = bindSym"fromVm"
  if not returnType.eqIdent("void"):
    retNode.add nnkAsgn.newTree(resultIdnt, newCall(fromVm, returnType, retName))
    retNode.add resultIdnt

  let nsProc = genSym(nskLet, "nsProc")
  var nsCall: NimNode
  if args.len > 0:
    let count = newLit(args.len)
    convs.add quote do:
      var `argSym`: array[`count`, PNode]
    nsCall = quote do:
      `intr`.callRoutine(`nsProc`, `argSym`)
  else:
    nsCall = quote do:
      `intr`.callRoutine(`nsProc`, [])

  for i, arg in args:
    convs.add quote do:
      `argSym`[`i`] = toVm(`arg`)

  result = quote do:
    block:
      when `returnType` isnot void:
        var `resultIdnt`: `returnType`
      let `nsProc` = `intr`.selectRoutine(`procName`)
      if `nsProc` != nil:
        `convs`
        when `returnType` isnot void:
          let `retName` = `nsCall`
          `retNode`
        else:
          `nsCall`
      else:
        raise newException(VmProcNotFound, "'$#' was not found in the script." % `procName`)
