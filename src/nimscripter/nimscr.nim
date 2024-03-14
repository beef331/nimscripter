## This is a interopable version of the Nimscript module, there be dragons.
## If done properly this should allow interop from any language to Nimscript in an easy way.
## A lot of duplicated code that is done in a smarter safer way.
const isLib = compileOption("app", "lib") or compileOption("app", "staticlib")

import "$nim" / compiler / [nimeval, renderer, ast, lineinfos, vmdef]
import std/[os, sugar, strutils, tempfiles]
export Severity, TNodeKind, VmArgs, TRegisterKind

when isLib:
  import pkg/seeya
  import std / [strformat, tables, strscans]
  import "$nim" / compiler / [llstream, vm, options, types]
  static: setFormatter("nimscripter_$1")
else:
  import vmconversion
  import std/typetraits
  import assume/typeit

when isLib:
  {.pragma: nimscrintrp, exportc"nimscripter_$1", dynlib, cdecl.}
else:
  const
    nimscrlib =
      when defined(linux):
        "libnimscr.so"
      elif defined(windows):
        "nimscr.dll"
      else: # TODO: Add BSD and other OS support
        "nimscr.dylib"
  {.pragma: nimscrintrp, dynlib: nimscrlib, cdecl.}

proc nstr(s: string): string {.used.} = "nimscripter_" & s


type
  VmProcSignature* = object
    package*, name*, module*: cstring
    vmProc*: proc(node: VmArgs) {.cdecl, gcsafe.}

  VmAddins* = object
    procs*: ptr UncheckedArray[VmProcSignature]
    procLen*: int
    additions*: cstring
    postCodeAdditions*: cstring

  Defines* = object
    left, right: cstring

  ErrorHook* = proc(fileName: cstring, line, col: int, msg: cstring, severity: Severity) {.cdecl.}
  VmQuit = object of CatchableError
  WrappedPNode* = distinct PNode

  Version* = object
    major*, minor*, patch*: uint8

  Inter = ptr typeof(Interpreter()[])

  WrappedInterpreter* = object
    intr: Inter
    path, tempBuffer: string

when isLib:
  type
    SaveEntry = object
      val: PNode
      typ: PType
      name: string
    SaveState* = ref seq[SaveEntry]
else:
  type
    SaveStateImpl = ref object
    SaveState* = distinct SaveStateImpl 

proc define*(a, b: static cstring): Defines = Defines(left: a, right: b)

const defaultDefines* = [define("nimscript", "true"), define("nimconfig", "true")]

proc `=destroy`*(pnode: WrappedPNode)

when not isLib:
  proc destroy*(val: sink WrappedPNode) {.nimscrintrp, importc: nstr"destroy_pnode".}
  proc destroy*(intr: sink WrappedInterpreter) {.nimscrintrp, importc: nstr"destroy_interpreter".}
  proc destroy*(intr: sink SaveState) {.nimscrintrp, importc: nstr"destroy_save_state".}

else:
  converter toInterpreter(inter: Inter): Interpreter = cast[Interpreter](inter)

  proc toCType(_: typedesc[WrappedPNode], name: string, isProc: bool): string =
    toCtype(OpaqueRef[PNode], name, isProc)

  proc toTypeDefs(_: typedesc[WrappedPNode]): string =
    addType(OpaqueRef[PNode])

  proc toCType(T: typedesc[PNode or SaveState or PType or Inter], name: string, isProc: bool): string =
    toCtype(OpaqueRef[T], name, isProc)

  proc toTypeDefs(T: typedesc[PNode or SaveState or PType or Inter]): string =
    addType(OpaqueRef[T])

proc `=destroy`*(pnode: WrappedPNode) =
  when isLib:
    `=destroy`(PNode pnode)
  else:
    destroy(pnode)

proc `=destroy`*(intr: WrappedInterpreter) =
  when isLib:
    if intr.intr != nil:
      `=destroy`(cast[Interpreter](intr.intr))
    `=destroy`(intr.path)
  else:
    destroy(intr)

when not isLib:
  proc `=destroy`*(intr: SaveState) =
    destroy(intr)

proc isValid*(intr: WrappedInterpreter): bool = intr.intr != nil

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
  if paths.len > 0:
    for path in paths:
      if path != nil:
        result.add $path

when isLib:
  var errorHook {.exportc: "nimscripter_$1", dynlib, expose.}: ErrorHook
  var version* {.exportc: "nimscripter_$1", dynlib, expose.} = static:
    let 
      val = staticExec"git describe --tags"
      (_, major, minor, patch) = val.scanTuple("v$i.$i.$i")
    Version(major: uint8 major, minor: uint8 minor, patch: uint8 patch)
  var do_log {.exportc: "nimscripter_$1", dynlib, expose.} = false

  proc log(msg: varargs[string, `$`]) =
    if do_log:
      try:
        for ms in msg:
          stdout.write ms
        stdout.write "\n"
        stdout.flushFile()
      except CatchableError:
        discard
else:
  var errorHook* {.importc:"nimscripter_$1", dynlib: nimscrlib.}: ErrorHook
  var internalVersion {.exportc: "nimscripter_version", dynlib: nimscrlib, noinit.}: Version
  let version* = internalVersion

proc implementAddins(intr: Interpreter, scriptName: string, modules: openarray[cstring], addins: VmAddins) =
  for uProc in addins.procs.toOpenArray(0, addins.procLen - 1):
    capture uProc:
      let anonProc = proc(args: VmArgs){.closure, gcsafe.} = 
        uProc.vmProc(args)
      intr.implementRoutine($uProc.package, $uProc.module, $uProc.name, anonProc)

when isLib:

  proc dafuq(): WrappedInterpreter {.expose, nimscrintrp.} =
    var s = WrappedInterpreter()


  proc load_script(
    script: cstring;
    addins: VMAddins;
    searchPaths: openArray[cstring];
    stdPath: cstring;
    defines: openArray[Defines]
  ): WrappedInterpreter {.nimscrintrp, raises: [], expose.} =

    log "Loading script: ", $script
    let
      scriptPath = $script
      (scriptDir, scriptName, _) = scriptPath.splitFile()
      scriptNimble = scriptDir / scriptName.changeFileExt(".nimble")
    try:
      log "Write nimble file at: ", scriptNimble
      writeFile(scriptNimble, "")
    except IoError, OsError:
      return 

    var searchPaths = 
      try:
        log "Attemping to create search paths"
        echo searchPaths.len
        getSearchPath($stdPath) & searchPaths.convertSearchPaths()
      except IoError, OsError:
        echo getCurrentExceptionMsg()
        return

    searchPaths.add scriptDir

    let
      intr =
        try:
          log "Attempting to create interpreter"
          createInterpreter(scriptPath, searchPaths, flags = {allowInfiniteLoops},
            defines = convertDefines defines
          )
        except Exception:
          echo getCurrentExceptionMsg()
          return

    intr.implementAddins(scriptName, [], addins)

    searchPaths.add scriptDir

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
      log "Intepret script"
      let scriptFile = open(scriptPath)
      intr.evalScript(llStreamOpen(scriptFile))
      log "Script evaluated"
      var res = WrappedInterpreter(intr: cast[Inter](intr), path: scriptPath, tempBuffer: genTempPath("", "", getTempDir()))
      try:
        log "Attempt to create temp buffer"
        discard existsOrCreateDir(result.tempBuffer.parentDir)
        copyFile(scriptPath, result.tempBuffer)
      except ValueError, OsError, IoError:
        echo "Error creating temp buffer: ", getCurrentExceptionMsg()
        return
      return res



    except IoError, OsError, ESuggestDone, ValueError, Exception, VmQuit:
      echo getCurrentExceptionMsg()
      return

  proc reload_script*(intr: var WrappedInterpreter, keepBest: bool = false) {.nimscrintrp, raises: [], expose.} =
    try:
      let scriptFile = open(intr.path)
      intr.intr.evalScript(llStreamOpen(scriptFile))
      if keepBest:
        copyFile(intr.path, intr.tempBuffer)
    except IoError, OsError, ESuggestDone, ValueError, Exception, VmQuit:
      try:
        if keepBest:
          let scriptFile = open(intr.tempBuffer)
          intr.intr.evalScript(llStreamOpen(scriptFile))
      except IoError, OsError, ESuggestDone, ValueError, Exception, VmQuit:
        echo getCurrentExceptionMsg()

  proc new_node*(kind: TNodeKind): WrappedPNode {.nimscrintrp, expose.} = ast.newNode(kind)

  proc pnode_add*(node, toAdd: WrappedPNode) {.nimscrintrp, expose.} = PNode(node).add toAdd


  proc int_node*(val: int): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkIntLit, val.BiggestInt)
  proc int8_node*(val: int8): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkInt8Lit, val.BiggestInt)
  proc int16_node*(val: int16): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkInt16Lit, val.BiggestInt)
  proc int32_node*(val: int32): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkInt32Lit, val.BiggestInt)
  proc int64_node*(val: int64): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkInt64Lit, val.BiggestInt)

  proc uint_node*(val: uint): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkuIntLit, val.BiggestInt)
  proc uint8_node*(val: uint8): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkuInt8Lit, val.BiggestInt)
  proc uint16_node*(val: uint16): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkuInt16Lit, val.BiggestInt)
  proc uint32_node*(val: uint32): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkuInt32Lit, val.BiggestInt)
  proc uint64_node*(val: uint64): WrappedPNode {.nimscrintrp, expose.} = newIntNode(nkuInt64Lit, val.BiggestInt)


  proc float_node*(val: float32): WrappedPNode {.nimscrintrp, expose.} = newFloatNode(nkFloat32Lit, val.BiggestFloat)
  proc double_node*(val: float): WrappedPNode {.nimscrintrp, expose.} = newFloatNode(nkFloat64Lit, val.BiggestFloat)

  proc string_node*(val: cstring): WrappedPNode {.nimscrintrp, expose.} = newStrNode(nkStrLit, $val)
  # Should we expose a `string` API across the C bridge?
  # We then could take in `string` everywhere and not have to copy as much in lib.
  # Though it still copies...


  proc pnode_index*(val: WrappedPNode, ind: int): WrappedPNode {.nimscrintrp, expose.} =
    if val.len < ind:
      result = val[ind]

  proc pnode_index_field*(val: WrappedPNode, ind: int): WrappedPNode {.nimscrintrp, expose.} =
    if val.len < ind and val[ind].len == 2:
      result = val[ind][1]

  proc pnode_get_int*(val: WrappedPNode, dest: var BiggestInt): bool {.nimscrintrp, expose.} =
    if PNode(val).kind in {nkCharLit..nkUInt64Lit}:
      result = true
      dest = PNode(val).intVal

  proc pnode_get_double*(val: WrappedPNode, dest: var BiggestFloat): bool {.nimscrintrp, expose.} =
    if PNode(val).kind in {nkFloatLit..nkFloat64Lit}:
      result = true
      dest = PNode(val).floatVal

  proc pnode_get_float*(val: WrappedPNode, dest: var float32): bool {.nimscrintrp, expose.} =
    if PNode(val).kind in {nkFloatLit..nkFloat64Lit}:
      result = true
      dest = float32 PNode(val).floatVal

  proc pnode_get_string*(val: WrappedPNode, dest: var cstring): bool {.nimscrintrp, expose.} =
    if PNode(val).kind in {nkStrLit..nkTripleStrLit}:
      result = true
      dest = cstring PNode(val).strVal

  proc invoke*(intr: WrappedInterpreter, name: cstring, args: openArray[WrappedPNode]): WrappedPNode {.nimscrintrp, expose.} =
    let
      intr {.cursor.} = intr.intr
      prcSym = intr.selectRoutine($name)
    if prcSym != nil:
      if args.len == 0:
        result = callRoutine(intr, prcSym, [])
      else:
        let arr = cast[ptr UncheckedArray[PNode]](args[0].addr)
        result = callRoutine(intr, prcSym, arr.toOpenArray(0, args.high))

  proc invoke_node_name*(intr: WrappedInterpreter, name: WrappedPNode, args: openArray[WrappedPNode]): WrappedPNode {.nimscrintrp, expose.} =
    let 
      intr {.cursor.} = intr.intr
      name {.cursor.} = PNode name
    if name.kind != nkSym:
      echo "Cannot invoke: ", name.kind
    elif name != nil and name.sym != nil:
      if args.len == 0:
        result = callRoutine(intr, name.sym, [])
      else:
        let arr = cast[ptr UncheckedArray[PNode]](args[0].addr)
        result = callRoutine(intr, name.sym, arr.toOpenArray(0, args.high))


  proc pnode_get_kind*(node: WrappedPNode): TNodeKind {.nimscrintrp, expose.} = PNode(node).kind

  template getReg(a, i): untyped =
    doAssert i < a.rc-1
    a.slots[i+a.rb+1].unsafeAddr

  proc vmargs_get_kind*(args: VmArgs, i: Natural): TRegisterKind {.nimscrintrp, expose.} = args.getReg(i).kind
  proc vmargs_get_int*(args: VmArgs, i: Natural): BiggestInt {.nimscrintrp, expose.} = args.getInt(i)
  proc vmargs_get_bool*(args: VmArgs, i: Natural): bool {.nimscrintrp, expose.} = args.getInt(i) != 0
  proc vmargs_get_float*(args: VmArgs, i: Natural): BiggestFloat {.nimscrintrp, expose.} = args.getFloat(i)
  proc vmargs_get_node*(args: VmArgs, i: Natural): WrappedPNode {.nimscrintrp, expose.} = args.getNode(i)
  proc vmargs_get_string*(args: VmArgs, i: Natural): cstring {.nimscrintrp, expose.} = cstring vm.getString(args, i)

  proc vmargs_set_result_int*(args: VmArgs, val: BiggestInt) {.nimscrintrp, expose.} = args.setResult(val)
  proc vmargs_set_result_float*(args: VmArgs, val: BiggestFloat) {.nimscrintrp, expose.} = args.setResult(val)
  proc vmargs_set_result_string*(args: VmArgs, val: cstring) {.nimscrintrp, expose.} = args.setResult($val)
  proc vmargs_set_result_node*(args: VmArgs, val: WrappedPNode) {.nimscrintrp, expose.} = args.setResult(val)

  proc destroy_save_state*(pnode: WrappedPNode) {.nimscrintrp, expose.} = discard

  proc save_state*(intr: WrappedInterpreter): SaveState {.nimscrintrp, expose.} =
    new result
    for sym in intr.intr.exportedSymbols():
      if sym.kind == skVar:
        result[].add SaveEntry(val: intr.intr.getGlobalValue(sym), typ: sym.typ, name: sym.name.s)

  proc load_state*(intr: WrappedInterpreter, state: SaveState) {.nimscrintrp, expose.} =
    for x in state[]:
      let sym = intr.intr.selectUniqueSymbol(x.name, {skVar})
      if sym != nil and $sym.typ == $x.typ:
        intr.intr.setGlobalValue(sym, x.val)

  proc deinit*() {.nimscrintrp.} = GCfullCollect() # Collect all?


  proc destroy_interpreter*(intr: WrappedInterpreter) {.nimscrintrp, expose.} = discard
  proc destroy_pnode*(pnode: WrappedPNode) {.nimscrintrp, expose.} = discard


  makeHeader("tests/lib/nimscr.h")
  when defined(genHeader):
    static:
      headers.incl "nimscr_h"
      discard staticExec("clang-format -i ../../tests/lib/nimscr.h")
else:
  proc init*() {.nimscrintrp, importc: nstr"NimMain".}

  proc loadScript*(
    script: cstring;
    addins: VMAddins;
    searchPaths: openArray[cstring];
    stdPath: cstring; 
    defines: openArray[Defines] = defaultDefines
  ): WrappedInterpreter {.nimscrintrp, importc: nstr"load_script".}

  proc reload*(intr: var WrappedInterpreter, keepBest: bool = false){.nimscrintrp, importc: nstr"reload_script".}

  proc newNode*(kind: TNodeKind): WrappedPNode {.nimscrintrp, importc: nstr"new_node".}

  proc add*(node, toAdd: WrappedPNode) {.nimscrintrp, importc: nstr"pnode_add".}

  proc newNode*(val: int): WrappedPNode {.nimscrintrp, importc: nstr"int_node".}
  proc newNode*(val: int8): WrappedPNode {.nimscrintrp, importc: nstr"int8_node".}
  proc newNode*(val: int16): WrappedPNode {.nimscrintrp, importc: nstr"int16_node".}
  proc newNode*(val: int32): WrappedPNode {.nimscrintrp, importc: nstr"int32_node".}
  proc newNode*(val: int64): WrappedPNode {.nimscrintrp, importc: nstr"int64_node".}

  proc newNode*(val: uint): WrappedPNode {.nimscrintrp, importc: nstr"uint_node".}
  proc newNode*(val: uint8): WrappedPNode {.nimscrintrp, importc: nstr"uint8_node".}
  proc newNode*(val: uint16): WrappedPNode {.nimscrintrp, importc: nstr"uint16_node".}
  proc newNode*(val: uint32): WrappedPNode {.nimscrintrp, importc: nstr"uint32_node".}
  proc newNode*(val: uint64): WrappedPNode {.nimscrintrp, importc: nstr"uint64_node".}

  proc newNode*(val: float32): WrappedPNode {.nimscrintrp, importc: nstr"float_node".}
  proc newNode*(val: float): WrappedPNode {.nimscrintrp, importc: nstr"double_node".}

  proc newNode*(val: cstring): WrappedPNode {.nimscrintrp, importc: nstr"string_node".}

  proc newNode*(val: enum or bool): WrappedPNode = BiggestInt(val).newNode()

  proc `[]`*(val: WrappedPNode, ind: int): WrappedPNode {.nimscrintrp, importc: nstr"pnode_index".}
  
  proc getInt*(val: WrappedPNode, dest: var BiggestInt): bool {.nimscrintrp, importc: nstr"pnode_get_int".}

  proc getDouble*(val: WrappedPNode, dest: var BiggestFloat): bool {.nimscrintrp, importc: nstr"pnode_get_double".}

  proc getFloat*(val: WrappedPNode, dest: var float32): bool {.nimscrintrp, importc: nstr"pnode_get_float".}

  proc getString*(val: WrappedPNode, dest: var cstring): bool {.nimscrintrp, importc: nstr"pnode_get_string".}

  proc invoke*(intr: WrappedInterpreter, name: cstring, args: openArray[WrappedPNode]): WrappedPNode {.nimscrintrp, importc: nstr"invoke".}
  proc invoke*(intr: WrappedInterpreter, name: WrappedPNode, args: openArray[WrappedPNode]): WrappedPNode {.nimscrintrp, importc: nstr"invoke_node_name".}

  proc kind*(node: WrappedPNode): TNodeKind {.nimscrintrp, importc: nstr"pnode_get_kind".}

  proc getKind*(args: VmArgs, i: Natural): TRegisterKind {.nimscrintrp, importc: nstr"vmargs_get_kind".} 
  proc getInt*(args: VmArgs, i: Natural): BiggestInt {.nimscrintrp, importc: nstr"vmargs_get_int".}
  proc getBool*(args: VmArgs, i: Natural): bool {.nimscrintrp, importc: nstr"vmargs_get_bool".}
  proc getFloat*(args: VmArgs, i: Natural): BiggestFloat {.nimscrintrp, importc: nstr"vmargs_get_float".}
  proc getNode*(args: VmArgs, i: Natural): WrappedPNode {.nimscrintrp, importc: nstr"vmargs_get_node".}
  proc getString*(args: VmArgs, i: Natural): cstring {.nimscrintrp, importc: nstr"vmargs_get_string".}

  proc setResult*(args: VmArgs, val: BiggestInt) {.nimscrintrp, importc: nstr"vmargs_set_result_int".}
  proc setResult*(args: VmArgs, val: SomeOrdinal or enum or bool) = args.setResult(BiggestInt(val))
  proc setResult*(args: VmArgs, val: BiggestFloat) {.nimscrintrp, importc: nstr"vmargs_set_result_float".}
  proc setResult*(args: VmArgs, val: cstring) {.nimscrintrp, importc: nstr"vmargs_set_result_string".}
  proc setResult*(args: VmArgs, val: string) = args.setResult(cstring val)
  proc setResult*(args: VmArgs, val: sink WrappedPNode) {.nimscrintrp, importc: nstr"vmargs_set_result_node".}

  proc saveState*(intr: WrappedInterpreter): SaveState {.nimscrintrp, importc: nstr"save_state".}
  proc loadState*(intr: WrappedInterpreter, saveState: SaveState) {.nimscrintrp, importc: nstr"load_state".}

  proc deinit*() {.nimscrintrp, importc: nstr"deinit".}

  proc fromVm*(t: typedesc, node: WrappedPNode): t =
    fromVm(t, Pnode(node))

  proc newNode*[T: string](a: T): WrappedPNode = newNode(cstring a)
  proc newNode*[T: proc](a: T): WrappedPNode = nimscr.newNode(nkNilLit)

  proc newNode*[T](s: set[T]): WrappedPNode =
    result = nimscr.newNode(nkCurly)
    let count = high(T).ord - low(T).ord
    result.sons.setLen(count)
    for val in s:
      let offset = val.ord - low(T).ord
      result[offset] = newNode(val)

  proc newNode*[T: openArray](obj: T): WrappedPNode
  proc newNode*[T: tuple](obj: T): WrappedPNode
  proc newNode*[T: object](obj: T): WrappedPNode
  proc newNode*[T: ref](obj: T): WrappedPNode
  proc newNode*[T: distinct](a: T): WrappedPNode = newNode(distinctBase(T, true)(a))
  proc newNode*[T: openArray](obj: T): WrappedPNode =
    result = nimscr.newNode(nkBracketExpr)
    for x in obj:
      result.add nimscr.newNode(x)

  proc newNode*[T: tuple](obj: T): WrappedPNode =
    result = nimscr.newNode(nkTupleConstr)
    for x in obj.fields:
      result.add newNode(x)

  proc newNode*[T: object](obj: T): WrappedPNode =
    result = nimscr.newNode(nkObjConstr)
    result.add nimscr.newNode(nkEmpty)
    typeit(obj, {titAllFields}):
      result.add nimscr.newNode(nkEmpty)
    var i = 1
    typeIt(obj, {titAllFields, titDeclaredOrder}):
      if it.isAccessible:
        result[i] = nimscr.newNode(nkExprColonExpr)
        result[i].add nimscr.newNode(nkEmpty)
        result[i].add newNode(it)
      inc i

  proc newNode*[T: ref](obj: T): WrappedPNode =
    if obj.isNil:
      nimscr.newNode(nkNilLit)
    else:
      nimscr.newNode(obj[])