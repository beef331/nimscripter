import compiler / [nimeval, renderer, ast, llstream, lineinfos, idents, types]
import std/[os, json, options, strutils, macros]
import nimscripter/[expose, vmconversion]
export destroyInterpreter, options, Interpreter, ast, lineinfos, idents

import nimscripter/procsignature

type
  VMQuit* = object of CatchableError
    info*: TLineInfo
  VmProcNotFound* = object of CatchableError
  NimScriptFile* = distinct string
  NimScriptPath* = distinct string
  SavedVar = object
    name: string
    typ: PType
    val: Pnode
  SaveState* = seq[SavedVar]

proc getSearchPath(path: string): seq[string] =
  result.add path
  for dir in walkDirRec(path, {pcDir}):
    result.add dir

proc errorHook(config, info, msg, severity: auto) {.gcsafe.} =
  if severity == Error and config.error_counter >= config.error_max:
    echo "Script Error: ", info, " ", msg
    raise (ref VMQuit)(info: info, msg: msg)

when declared(nimeval.setGlobalValue):
  proc saveState*(intr: Interpreter): SaveState =
    for x in intr.exportedSymbols():
      if x.kind in {skVar, skLet}:
        let
          val = intr.getGlobalValue(x)
          typ = x.typ
          name = x.name.s
        result.add SavedVar(name: name, typ: typ, val: val)

  proc loadState*(intr: Interpreter, state: SaveState) = 
    for x in state:
      let sym = intr.selectUniqueSymbol(x.name, {skLet, skVar})
      if sym != nil and sameType(sym.typ, x.typ):
        intr.setGlobalValue(sym, x.val)

proc loadScript*(
  script: NimScriptFile or NimScriptPath,
  userProcs: openArray[VmProcSignature],
  additions = "",
  modules: varargs[string],
  stdPath = findNimStdlibCompileTime()): Option[Interpreter] =
  const isFile = script is NimScriptPath
  if not isFile or fileExists(script.string):
    var additions = additions
    for `mod` in modules: # Add modules
      additions.insert("import " & `mod` & "\n", 0)

    for uProc in userProcs:
      additions.add uProc.vmRunImpl

    var searchPaths = getSearchPath(stdPath)
    let scriptName = when isFile: script.string.splitFile.name else: "script"

    when isFile: # If is file we want to enable relative imports
      searchPaths.add script.string.parentDir

    let
      intr = createInterpreter(scriptName, searchPaths)
      script = when isFile: readFile(script.string) else: script.string

    for uProc in userProcs:
      intr.implementRoutine("*", scriptName, uProc.name, uProc.vmProc)

    when defined(debugScript): writeFile("debugScript.nims", additions & script)
    intr.registerErrorHook(errorHook)
    try:
      intr.evalScript(llStreamOpen(additions & script))
      result = option(intr)
    except: discard

proc loadScriptWithState*(
  intr: var Option[Interpreter],
  script: NimScriptFile or NimScriptPath,
  userProcs: openArray[VmProcSignature],
  additions = "",
  modules: varargs[string],
  stdPath = findNimStdlibCompileTime()) =
  ## Saves state, then loads the intepreter into `intr`.
  ## This does not keep a working intepreter if there is a script error.
  let state = 
    if intr.isSome:
      intr.get.saveState()
    else:
      @[]
  intr = loadScript(script, userProcs, additions, modules, stdPath)
  if intr.isSome:
    intr.get.loadState(state)

proc safeloadScriptWithState*(
  intr: var Option[Interpreter],
  script: NimScriptFile or NimScriptPath,
  userProcs: openArray[VmProcSignature],
  additions = "",
  modules: varargs[string],
  stdPath = findNimStdlibCompileTime()) =
  ## Saves state, then loads the intepreter into `intr` if there were no script errors.
  ## Prefers a working interpreter.
  let state = 
    if intr.isSome:
      intr.get.saveState()
    else:
      @[]
  let tempIntr = loadScript(script, additions, modules, stdPath)
  if tempIntr.isSome:
    intr = tempIntr
    intr.loadState(state)

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
