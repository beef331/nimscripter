## This is a interopable version of the Nimscript module, there be dragons.
## If done properly this should allow interop from any language to Nimscript in an easy way.
## A lot of duplicated code that is done in a smarter safer way.

import "$nim"/compiler / [nimeval, renderer, ast, llstream, lineinfos, idents, types, options, vmdef]
import std/[os, json, strutils, macros, tables, sugar]


type
  VmProcSignature* {.bycopy.} = object
    name: cstring
    runtimeImpl: cstring
    vmProc: proc(node: VmArgs) {.cdecl, gcsafe.}

  VmAddins* {.bycopy.} = object
    procs*: ptr UncheckedArray[VmProcSignature]
    procLen*: int
    additions*: cstring
    postCodeAdditions*: cstring

  Defines* {.bycopy.} = object
    left, right: cstring

  ErrorHook* = proc(fileName: cstring, line, col: int, msg: cstring, severity: Severity) {.cdecl.}
  VmQuit = object of CatchableError

proc getSearchPath(path: string): seq[string] =
  result.add path
  for dir in walkDirRec(path, {pcDir}):
    result.add dir

proc convertDefines(args: openArray[Defines]): seq[(string, string)] = # This is dumb as all hell
  for x in args:
    result.add ($x.left, $x.right)

proc convertSearchPaths(paths: openArray[cstring]): seq[string] =
  for path in paths:
    result.add $path 

var nimscripter_error_hook {.exportc, dynlib.}: ErrorHook


proc implementAddins(intr: Interpreter, scriptFile: File, scriptName: string, modules: openarray[cstring], addins: VmAddins) =
 
  for modu in modules:
    scriptFile.write "import "
    scriptFile.writeLine modu
  
  if addins.additions != nil:
    scriptFile.write addins.additions

  for uProc in addins.procs.toOpenArray(0, addins.procLen - 1):
    capture uProc:
      let anonProc = proc(args: VmArgs){.closure, gcsafe.} = 
        uProc.vmProc(args)
      intr.implementRoutine(scriptName, scriptName, $uProc.name, anonProc)


static: echo findNimStdLibCompileTime()

proc nimscripter_load_script*(
  script: cstring;
  addins: VMAddins;
  modules: openArray[cstring];
  searchPaths: openArray[cstring];
  stdPath: cstring; 
  defines: openArray[Defines]
): Interpreter {.exportc, dynlib.} =
  ## Loads an interpreter from a file or from string, with given addtions and userprocs.
  ## To load from the filesystem use `NimScriptPath(yourPath)`.
  ## To load from a string use `NimScriptFile(yourFile)`.
  ## `addins` is the overrided procs/addons from `impleNimScriptModule
  ## `modules` implict imports to add to the module.
  ## `stdPath` to use shipped path instead of finding it at compile time.
  ## `searchPaths` optional paths one can use to supply libraries or packages for the
  var searchPaths = getSearchPath($stdPath) & searchPaths.convertSearchPaths()
  let
    script = $script
    scriptName = script.splitFile.name
    scriptDir = getTempDir() / scriptName
    scriptNimble = scriptDir / scriptName.changeFileExt(".nimble")
    scriptPath = scriptDir / scriptName.changeFileExt(".nim")

  discard existsOrCreateDir(scriptDir)
  writeFile(scriptNimble, "")

  let scriptFile = open(scriptPath, fmReadWrite)

  searchPaths.add scriptDir


  let
    intr = createInterpreter(scriptPath, searchPaths, flags = {allowInfiniteLoops},
      defines = convertDefines defines
    )

  intr.implementAddins(scriptFile, scriptName, modules, addins)

  scriptFile.write readFile(script)
  searchPaths.add script.parentDir

  if addins.postCodeAdditions != nil:
    scriptFile.write $addins.postCodeAdditions

  intr.registerErrorHook proc(config: ConfigRef, info: TLineInfo, msg: string, sev: Severity) {.nimcall, gcSafe.} = 
    if sev == Error and config.error_counter >= config.error_max:
      var fileName: string
      for k, v in config.m.filenameToIndexTbl.pairs:
        if v == info.fileIndex:
          fileName = k

      {.cast(gcSafe).}:
        if nimscripter_error_hook != nil:
          nimscripter_error_hook(cstring fileName, int info.line, int info.col, msg, sev)

      raise (ref VMQuit)(msg: msg)

  try:
    scriptFile.setFilePos(0)
    intr.evalScript(llStreamOpen(scriptFile))
    result = intr
  except VMQuit:
    discard

proc nimscripter_load_string*(
  str: cstring;
  addins: VMAddins;
  modules: openArray[cstring];
  searchPaths: openArray[cstring];
  stdPath: cstring; 
  defines: openArray[Defines]
): Interpreter {.exportc, dynlib.} =
  ## Loads an interpreter from a from string, with given addtions and userprocs.
  ## To load from the filesystem use `NimScriptPath(yourPath)`.
  ## To load from a string use `NimScriptFile(yourFile)`.
  ## `addins` is the overrided procs/addons from `impleNimScriptModule
  ## `modules` implict imports to add to the module.
  ## `stdPath` to use shipped path instead of finding it at compile time.
  ## `searchPaths` optional paths one can use to supply libraries or packages for the
  var searchPaths = getSearchPath($stdPath) & @searchPaths.convertSearchPaths()
  let
    script = "script"
    scriptName = script.splitFile.name
    scriptDir = getTempDir() / scriptName
    scriptNimble = scriptDir / scriptName.changeFileExt(".nimble")
    scriptPath = scriptDir / scriptName.changeFileExt(".nim")

  discard existsOrCreateDir(scriptDir)
  writeFile(scriptNimble, "")

  let scriptFile = open(scriptPath, fmReadWrite)

  searchPaths.add scriptDir


  let
    intr = createInterpreter(scriptPath, searchPaths, flags = {allowInfiniteLoops},
      defines = convertDefines defines
    )

  intr.implementAddins(scriptFile, scriptName, modules, addins)

  scriptFile.write str
  searchPaths.add script.parentDir

  scriptFile.write $addins.postCodeAdditions

  intr.registerErrorHook proc(config: ConfigRef, info: TLineInfo, msg: string, sev: Severity) {.nimcall, gcSafe.} = 
    if sev == Error and config.error_counter >= config.error_max:
      var fileName: string
      for k, v in config.m.filenameToIndexTbl.pairs:
        if v == info.fileIndex:
          fileName = k

      {.cast(gcSafe).}:
        if nimscripter_error_hook != nil:
          nimscripter_error_hook(cstring fileName, int info.line, int info.col, msg, sev)

      raise (ref VMQuit)(msg: msg)

  try:
    scriptFile.setFilePos(0)
    intr.evalScript(llStreamOpen(scriptFile))
    result = intr
  except VMQuit:
    discard

proc nimscripter_destroy_interpreter*(intr: Interpreter) {.exportc, dynlib.} =
  GC_unref(intr)
  destroyInterpreter(intr)

proc nimscripter_int_node*(val: int): PNode {.exportc, dynlib.} = newIntNode(nkIntLit, val.BiggestInt)
proc nimscripter_int8_node*(val: int8): PNode {.exportc, dynlib.} = newIntNode(nkInt8Lit, val.BiggestInt)
proc nimscripter_int16_node*(val: int16): PNode {.exportc, dynlib.} = newIntNode(nkInt16Lit, val.BiggestInt)
proc nimscripter_int32_node*(val: int32): PNode {.exportc, dynlib.} = newIntNode(nkInt32Lit, val.BiggestInt)
proc nimscripter_int64_node*(val: int64): PNode {.exportc, dynlib.} = newIntNode(nkInt64Lit, val.BiggestInt)

proc nimscripter_uint_node*(val: uint): PNode {.exportc, dynlib.} = newIntNode(nkuIntLit, val.BiggestInt)
proc nimscripter_uint8_node*(val: uint8): PNode {.exportc, dynlib.} = newIntNode(nkuInt8Lit, val.BiggestInt)
proc nimscripter_uint16_node*(val: uint16): PNode {.exportc, dynlib.} = newIntNode(nkuInt16Lit, val.BiggestInt)
proc nimscripter_uint32_node*(val: uint32): PNode {.exportc, dynlib.} = newIntNode(nkuInt32Lit, val.BiggestInt)
proc nimscripter_uint64_node*(val: uint64): PNode {.exportc, dynlib.} = newIntNode(nkuInt64Lit, val.BiggestInt)


proc nimscripter_float_node*(val: float32): PNode {.exportc, dynlib.} = newFloatNode(nkFloat32Lit, val.BiggestFloat)
proc nimscripter_double_node*(val: float): PNode {.exportc, dynlib.} = newFloatNode(nkFloat64Lit, val.BiggestFloat)

proc nimscripter_string_node*(val: cstring): PNode {.exportc, dynlib.} = newStrNode(nkStrLit, $val)

proc nimscripter_destroy_pnode*(val: PNode) {.exportc, dynlib.} =
  GcUnref(val)


proc nimscripter_invoke*(intr: Interpreter, name: cstring, args: ptr UncheckedArray[PNode], count: int): PNode {.exportc, dynlib.} =
  let prcSym = intr.selectRoutine($name)
  if prcSym != nil:
    if count > 0:
      result = intr.callRoutine(prcSym, args.toOpenArray(0, count))
    else:
      result = intr.callRoutine(prcSym, [])  
