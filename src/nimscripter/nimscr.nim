## This is a interopable version of the Nimscript module, there be dragons.
## If done properly this should allow interop from any language to Nimscript in an easy way.
## A lot of duplicated code that is done in a smarter safer way.
import "$nim"/compiler / [nimeval, renderer, ast, llstream, lineinfos, options, vmdef, vm]
import std/[os, strformat, sugar, tables]
export Severity, TNodeKind, VmArgs




const
  isLib = defined(nimscripterlib)

when isLib:
  {.pragma: nimscrexport, exportc"nimscripter_$1", dynlib, cdecl}
else:
  const
    nimscrlib =
      when defined(linux):
        "libnimscr.so"
      elif defined(windows):
        "nimscr.dll"
      else: # TODO: Add BSD and other OS support
        "nimscr.dylib"
  {.pragma: nimscrexport, importc:"nimscripter_$1", dynlib: nimscrlib, cdecl}


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

proc define*(a, b: static cstring): Defines = Defines(left: a, right: b)

const defaultDefines* = [define("nimscript", "true"), define("nimconfig", "true")]
proc `=destroy`*(pnode: WrappedPNode)

proc destroyPnode*(val: WrappedPNode) {.nimscrexport.} =
  GcUnref(PNode(val))

proc `=destroy`*(pnode: WrappedPNode) = 
  destroyPnode(pnode)


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
  var errorHook* {.exportc: "nimscripter_$1", dynlib.}: ErrorHook
else:
  var errorHook* {.importc:"nimscripter_$1", dynlib: nimscrlib.}: ErrorHook

proc implementAddins(intr: Interpreter, scriptFile: File, scriptName: string, modules: openarray[cstring], addins: VmAddins) =
 
  for modu in modules:
    scriptFile.write "import "
    scriptFile.writeLine modu
  
  if addins.additions != nil:
    scriptFile.write addins.additions

  for uProc in addins.procs.toOpenArray(0, addins.procLen - 1):
    scriptfile.writeLine(uProc.runtimeImpl)
    capture uProc:
      let anonProc = proc(args: VmArgs){.closure, gcsafe.} = 
        uProc.vmProc(args)
      intr.implementRoutine(scriptName, scriptName, $uProc.name, anonProc)

proc loadScript*(
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
        if errorHook != nil:
          errorHook(cstring fileName, int info.line, int info.col, msg, sev)

      raise (ref VMQuit)(msg: msg)

  try:
    scriptFile.setFilePos(0)
    intr.evalScript(llStreamOpen(scriptFile))
    result = intr
  except VMQuit:
    discard

proc loadString*(
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
        if errorHook != nil:
          errorHook(cstring fileName, int info.line, int info.col, msg, sev)

      raise (ref VMQuit)(msg: msg)

  try:
    scriptFile.setFilePos(0)
    intr.evalScript(llStreamOpen(scriptFile))
    result = intr
  except VMQuit:
    discard

proc destroyInterpreter*(intr: Interpreter) {.nimscrexport.} =
  GC_unref(intr)
  nimeval.destroyInterpreter(intr)

proc newNode*(kind: TNodeKind): WrappedPNode {.nimscrexport.} = ast.newNode(kind)

proc pnodeAdd*(node, toAdd: WrappedPNode) {.nimscrexport.} = PNode(node).add toAdd


proc intNode*(val: int): WrappedPNode {.nimscrexport.} = newIntNode(nkIntLit, val.BiggestInt)
proc int8Node*(val: int8): WrappedPNode {.nimscrexport.} = newIntNode(nkInt8Lit, val.BiggestInt)
proc int16Node*(val: int16): WrappedPNode {.nimscrexport.} = newIntNode(nkInt16Lit, val.BiggestInt)
proc int32Node*(val: int32): WrappedPNode {.nimscrexport.} = newIntNode(nkInt32Lit, val.BiggestInt)
proc int64Node*(val: int64): WrappedPNode {.nimscrexport.} = newIntNode(nkInt64Lit, val.BiggestInt)

proc uintNode*(val: uint): WrappedPNode {.nimscrexport.} = newIntNode(nkuIntLit, val.BiggestInt)
proc uint8Node*(val: uint8): WrappedPNode {.nimscrexport.} = newIntNode(nkuInt8Lit, val.BiggestInt)
proc uint16Node*(val: uint16): WrappedPNode {.nimscrexport.} = newIntNode(nkuInt16Lit, val.BiggestInt)
proc uint32Node*(val: uint32): WrappedPNode {.nimscrexport.} = newIntNode(nkuInt32Lit, val.BiggestInt)
proc uint64Node*(val: uint64): WrappedPNode {.nimscrexport.} = newIntNode(nkuInt64Lit, val.BiggestInt)


proc floatNode*(val: float32): WrappedPNode {.nimscrexport.} = newFloatNode(nkFloat32Lit, val.BiggestFloat)
proc doubleNode*(val: float): WrappedPNode {.nimscrexport.} = newFloatNode(nkFloat64Lit, val.BiggestFloat)

proc stringNode*(val: cstring): WrappedPNode {.nimscrexport.} = newStrNode(nkStrLit, $val)


proc pnodeIndex*(val: WrappedPNode, ind: int): WrappedPNode {.nimscrexport.} =
  if val.len < ind:
    result = val[ind]

proc pnodeIndexField*(val: WrappedPNode, ind: int): WrappedPNode {.nimscrexport.} =
  if val.len < ind and val[ind].len == 2:
    result = val[ind][1]

proc pnodeGetInt*(val: WrappedPNode, dest: var BiggestInt): bool {.nimscrexport.} =
  if PNode(val).kind in {nkCharLit..nkUInt64Lit}:
    result = true
    dest = PNode(val).intVal

proc pnodeGetDouble*(val: WrappedPNode, dest: var BiggestFloat): bool {.nimscrexport.} =
  if PNode(val).kind in {nkFloatLit..nkFloat64Lit}:
    result = true
    dest = PNode(val).floatVal

proc pnodeGetFloat*(val: WrappedPNode, dest: var float32): bool {.nimscrexport.} =
  if PNode(val).kind in {nkFloatLit..nkFloat64Lit}:
    result = true
    dest = float32 PNode(val).floatVal

proc pnodeGetString*(val: WrappedPNode, dest: var cstring): bool {.nimscrexport.} =
  if PNode(val).kind in {nkStrLit..nkTripleStrLit}:
    result = true
    dest = cstring PNode(val).strVal

proc invoke*(intr: Interpreter, name: cstring, args: openArray[WrappedPNode]): WrappedPNode {.nimscrexport.} =
  let prcSym = intr.selectRoutine($name)
  if prcSym != nil:
    if args.len == 0:
      result = callRoutine(intr, prcSym, [])
    else:
      let arr = cast[ptr UncheckedArray[PNode]](args[0].addr)
      result = callRoutine(intr, prcSym, arr.toOpenArray(0, args.high))

proc pnodeGetKind*(node: WrappedPNode): TNodeKind {.nimscrexport.} = PNode(node).kind

proc vmargsGetInt*(args: VmArgs, i: Natural): BiggestInt {.nimscrexport.} = args.getInt(i)
proc vmargsGetBool*(args: VmArgs, i: Natural): bool {.nimscrexport.} = args.getInt(i) != 0
proc vmargsGetFloat*(args: VmArgs, i: Natural): BiggestFloat {.nimscrexport.} = args.getFloat(i)
proc vmargsGetNode*(args: VmArgs, i: Natural): WrappedPNode {.nimscrexport.} = args.getNode(i)
proc vmargsGetString*(args: VmArgs, i: Natural): cstring {.nimscrexport.} = cstring args.getString(i)

when isLib:
  static: # Generate the kind enum
    var str = "enum nimscripter_pnode_kind {"
    for kind in TNodeKind:
      str.add fmt "\n\t{kind} = {ord(kind)}"
      if kind != TNodeKind.high:
        str.add ","
    str.add "};"
    writeFile("tests/lib/nimscr_kinds.h", str)



