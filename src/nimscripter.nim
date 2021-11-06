import compiler / [nimeval, renderer, ast, llstream, lineinfos, idents, types]
import compiler / options as copts
import std/[os, json, options, strutils, macros]
import nimscripter/[expose, vmaddins, vmconversion]
from compiler/vmdef import TSandboxFlag
export options, Interpreter, ast, lineinfos, idents, nimEval, expose, VMParseError

type
  VMQuit* = object of CatchableError
    info*: TLineInfo
  VMErrorHook* = proc (config: ConfigRef; info: TLineInfo; msg: string;
                              severity: Severity) {.gcsafe.}
  VmProcNotFound* = object of CatchableError
  VmSymNotFound* = object of CatchableError
  NimScriptFile* = distinct string ## Distinct to load from string
  NimScriptPath* = distinct string ## Distinct to load from path
  SavedVar = object
    name: string
    typ: PType
    val: Pnode
  SaveState* = seq[SavedVar]

proc getSearchPath(path: string): seq[string] =
  result.add path
  for dir in walkDirRec(path, {pcDir}):
    result.add dir

proc errorHook(config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) {.gcsafe.} =
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
  addins: VMAddins = VMaddins(),
  modules: varargs[string],
  vmErrorHook = errorHook,
  stdPath = findNimStdlibCompileTime()): Option[Interpreter] =
  ## Loads an interpreter from a file or from string, with given addtions and userprocs.
  ## To load from the filesystem use `NimScriptPath(yourPath)`.
  ## To load from a string use `NimScriptFile(yourFile)`.
  ## `addins` is the overrided procs/addons from `impleNimScriptModule
  ## `modules` implict imports to add to the module.
  ## `stdPath` to use shipped path instead of finding it at compile time.
  ## `vmErrorHook` a callback which should raise `VmQuit`, refer to `errorHook` for reference.
  const isFile = script is NimScriptPath
  if not isFile or fileExists(script.string):
    var additions = addins.additions
    for `mod` in modules: # Add modules
      additions.insert("import " & `mod` & "\n", 0)

    for uProc in addins.procs:
      additions.add uProc.vmRunImpl

    var searchPaths = getSearchPath(stdPath)
    let scriptName = when isFile: script.string.splitFile.name else: "script"

    when isFile: # If is file we want to enable relative imports
      searchPaths.add script.string.parentDir

    let
      intr = createInterpreter(scriptName, searchPaths, flags = {allowInfiniteLoops})
      script = when isFile: readFile(script.string) else: script.string

    for uProc in addins.procs:
      intr.implementRoutine("*", scriptName, uProc.name, uProc.vmProc)

    intr.registerErrorHook(vmErrorHook)
    try:
      additions.add script
      additions.add addins.postCodeAdditions
      intr.evalScript(llStreamOpen(additions))
      result = option(intr)
    except VMQuit: discard

proc loadScriptWithState*(
  intr: var Option[Interpreter],
  script: NimScriptFile or NimScriptPath,
  addins: VMAddins = VMaddins(),
  modules: varargs[string],
  vmErrorHook = errorHook,
  stdPath = findNimStdlibCompileTime()) =
  ## Same as loadScript, but saves state, then loads the intepreter into `intr`.
  ## This does not keep a working intepreter if there is a script error.
  let state = 
    if intr.isSome:
      intr.get.saveState()
    else:
      @[]
  intr = loadScript(script, addins, modules, vmErrorHook, stdPath)
  if intr.isSome:
    intr.get.loadState(state)

proc safeloadScriptWithState*(
  intr: var Option[Interpreter],
  script: NimScriptFile or NimScriptPath,
  addins: VMAddins = VMaddins(),
  modules: varargs[string],
  vmErrorHook = errorHook,
  stdPath = findNimStdlibCompileTime()) =
  ## Same as loadScriptWithState but saves state then loads the intepreter into `intr` if there were no script errors.
  ## Tries to keep the interpreter running.
  let state = 
    if intr.isSome:
      intr.get.saveState()
    else:
      @[]
  let tempIntr = loadScript(script, addins, modules, vmErrorHook, stdPath)
  if tempIntr.isSome:
    intr = tempIntr
    intr.get.loadState(state)

proc getGlobalVariable*[T](intr: Option[Interpreter] or Interpreter, name: string): T =
  ## Easy access of a global nimscript variable
  when intr is Option[Interpreter]:
    assert intr.isSome
    let intr = intr.get
  let sym = intr.selectUniqueSymbol(name)
  if sym != nil:
    fromVm(T, intr.getGlobalValue(sym))
  else:
    raise newException(VmSymNotFound, name & " is not a global symbol in the script.")

macro invoke*(intr: Interpreter, pName: untyped, args: varargs[typed],
  returnType: typedesc = void): untyped =
  ## Calls a nimscript function named `pName`, passing the `args`
  ## Converts the returned value to `returnType`
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

macro invoke*(intr: Option[Interpreter], pName: untyped, args: varargs[typed],
    returnType: typedesc = void): untyped =
  ## Invoke but takes an option and unpacks it, if `intr.`isNone, assertion is raised
  result = newCall("invoke", newCall("get", intr), pname)
  for x in args:
    result.add x
  result.add nnkExprEqExpr.newTree(ident"returnType",  returnType)
  result = quote do:
    assert `intr`.isSome
    `result`