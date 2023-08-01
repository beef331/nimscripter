## This is a interopable version of the Nimscript module, there be dragons.
## If done properly this should allow interop from any language to Nimscript in an easy way.
## A lot of duplicated code that is done in a smarter safer way.
import "$nim"/compiler / [nimeval, renderer, ast, llstream, lineinfos, options, vmdef]
import std/[os, strformat, sugar, tables]




const
  isLib = defined(nimscripterlib)


when isLib:
  {.pragma: nimscrexport, exportc, dynlib, cdecl}
else:
  const
    nimscrlib =
      when defined(linux):
        "libnimscr.so"
      elif defined(windows):
        "nimscr.dll"
      else: # TODO: Add BSD and other OS support
        "nimscr.dylib"
  {.pragma: nimscrexport, importc, dynlib: nimscrlib, cdecl}


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
  WrappedPNode* = distinct PNode

proc `=destroy`*(pnode: WrappedPNode)

proc nimscripter_destroy_pnode*(val: WrappedPNode) {.nimscrexport.} =
  GcUnref(PNode(val))

proc `=destroy`*(pnode: WrappedPNode) = 
  nimscripter_destroy_pnode(pnode)


converter toPNode*(wrapped: WrappedPNode): PNode = PNode(wrapped)
converter toPNode*(pnode: PNode): WrappedPNode = WrappedPNode(pnode)


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

when isLib:
  var nimscripter_error_hook {.exportc, dynlib.}: ErrorHook
else:
  var nimscripter_error_hook {.importc, dynlib: nimscrlib.}: ErrorHook

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

proc nimscripter_load_script*(
  script: cstring;
  addins: VMAddins;
  modules: openArray[cstring];
  searchPaths: openArray[cstring];
  stdPath: cstring; 
  defines: openArray[Defines]
): Interpreter {.nimscrexport.} =

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
): Interpreter {.nimscrexport.} =
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

proc nimscripter_destroy_interpreter*(intr: Interpreter) {.nimscrexport.} =
  GC_unref(intr)
  destroyInterpreter(intr)

proc nimscripter_int_node*(val: int): WrappedPNode {.nimscrexport.} = newIntNode(nkIntLit, val.BiggestInt)
proc nimscripter_int8_node*(val: int8): WrappedPNode {.nimscrexport.} = newIntNode(nkInt8Lit, val.BiggestInt)
proc nimscripter_int16_node*(val: int16): WrappedPNode {.nimscrexport.} = newIntNode(nkInt16Lit, val.BiggestInt)
proc nimscripter_int32_node*(val: int32): WrappedPNode {.nimscrexport.} = newIntNode(nkInt32Lit, val.BiggestInt)
proc nimscripter_int64_node*(val: int64): WrappedPNode {.nimscrexport.} = newIntNode(nkInt64Lit, val.BiggestInt)

proc nimscripter_uint_node*(val: uint): WrappedPNode {.nimscrexport.} = newIntNode(nkuIntLit, val.BiggestInt)
proc nimscripter_uint8_node*(val: uint8): WrappedPNode {.nimscrexport.} = newIntNode(nkuInt8Lit, val.BiggestInt)
proc nimscripter_uint16_node*(val: uint16): WrappedPNode {.nimscrexport.} = newIntNode(nkuInt16Lit, val.BiggestInt)
proc nimscripter_uint32_node*(val: uint32): WrappedPNode {.nimscrexport.} = newIntNode(nkuInt32Lit, val.BiggestInt)
proc nimscripter_uint64_node*(val: uint64): WrappedPNode {.nimscrexport.} = newIntNode(nkuInt64Lit, val.BiggestInt)


proc nimscripter_float_node*(val: float32): WrappedPNode {.nimscrexport.} = newFloatNode(nkFloat32Lit, val.BiggestFloat)
proc nimscripter_double_node*(val: float): WrappedPNode {.nimscrexport.} = newFloatNode(nkFloat64Lit, val.BiggestFloat)

proc nimscripter_string_node*(val: cstring): WrappedPNode {.nimscrexport.} = newStrNode(nkStrLit, $val)


proc nimscripter_pnode_index*(val: WrappedPNode, ind: int): WrappedPNode {.nimscrexport.} =
  if val.len < ind:
    result = val[ind]

proc nimscripter_pnode_index_field*(val: WrappedPNode, ind: int): WrappedPNode {.nimscrexport.} =
  if val.len < ind and val[ind].len == 2:
    result = val[ind][1]

proc nimscripter_pnode_get_int*(val: WrappedPNode, dest: var BiggestInt): bool {.nimscrexport.} =
  if PNode(val).kind in {nkCharLit..nkUInt64Lit}:
    result = true
    dest = PNode(val).intVal

proc nimscripter_pnode_get_double*(val: WrappedPNode, dest: var BiggestFloat): bool {.nimscrexport.} =
  if PNode(val).kind in {nkFloatLit..nkFloat64Lit}:
    result = true
    dest = PNode(val).floatVal

proc nimscripter_pnode_get_float*(val: WrappedPNode, dest: var float32): bool {.nimscrexport.} =
  if PNode(val).kind in {nkFloatLit..nkFloat64Lit}:
    result = true
    dest = float32 PNode(val).floatVal

proc nimscripter_pnode_get_string*(val: WrappedPNode, dest: var cstring): bool {.nimscrexport.} =
  if PNode(val).kind in {nkStrLit..nkTripleStrLit}:
    result = true
    dest = cstring PNode(val).strVal

proc nimscripter_invoke*(intr: Interpreter, name: cstring, args: ptr UncheckedArray[WrappedPNode], count: int): WrappedPNode {.nimscrexport.} =
  let prcSym = intr.selectRoutine($name)
  if prcSym != nil:
    if count > 0:
      result = intr.callRoutine(prcSym, cast[ptr UncheckedArray[PNode]](args).toOpenArray(0, count - 1))
    else:
      result = intr.callRoutine(prcSym, [])

proc nimscripter_pnode_get_kind*(node: WrappedPNode): TNodeKind {.nimscrexport.} = PNode(node).kind

when isLib:
  static: # Generate the kind enum
    var str = "enum nimscripter_pnode_kind {"
    for kind in TNodeKind:
      str.add fmt "\n\t{kind} = {ord(kind)}"
      if kind != TNodeKind.high:
        str.add ","
    str.add "};"
    writeFile("tests/lib/nimscr_kinds.h", str)



