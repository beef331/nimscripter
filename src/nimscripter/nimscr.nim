## This is a interopable version of the Nimscript module, there be dragons.
## If done properly this should allow interop from any language to Nimscript in an easy way.
## A lot of duplicated code that is done in a smarter safer way.
const isLib = defined(nimscripterlib)

import "$nim" / compiler / [nimeval, renderer, ast, lineinfos, vmdef]
import std/[os, sugar]
export Severity, TNodeKind, VmArgs

when isLib:
  import std / [strformat, tables]
  import "$nim" / compiler / [llstream, vm, options]
else:
  import vmconversion
  import std/typetraits
  import assume/typeit



when isLib:
  {.pragma: nimscrintrp, exportc"nimscripter_$1", dynlib, cdecl}
else:
  const
    nimscrlib =
      when defined(linux):
        "libnimscr.so"
      elif defined(windows):
        "nimscr.dll"
      else: # TODO: Add BSD and other OS support
        "nimscr.dylib"
  {.pragma: nimscrintrp, dynlib: nimscrlib, cdecl}

proc nstr(s: string): string {.used.} = "nimscripter_" & s

type
  VmProcSignature* {.bycopy.} = object
    name*, module*: cstring
    runtimeImpl*: cstring
    vmProc*: proc(node: VmArgs) {.cdecl, gcsafe.}

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
  WrappedInterpreter* = distinct Interpreter


proc define*(a, b: static cstring): Defines = Defines(left: a, right: b)

const defaultDefines* = [define("nimscript", "true"), define("nimconfig", "true")]

proc `=destroy`*(pnode: WrappedPNode)

when not isLib:
  proc destroy*(val: sink WrappedPNode) {.nimscrintrp, importc: nstr"destroy_pnode".}
  proc destroy*(intr: sink WrappedInterpreter) {.nimscrintrp, importc: nstr"destroy_interpreter".}


proc `=destroy`*(pnode: WrappedPNode) =
  when isLib:
    `=destroy`(PNode pnode)
  else:
    destroy(pnode)

proc `=destroy`*(intr: WrappedInterpreter) =
  when isLib:
    `=destroy`(Interpreter intr)
  else:
    destroy(intr)

converter toPNode*(wrapped: WrappedPNode): PNode = PNode(wrapped)
converter toPNode*(pnode: PNode): WrappedPNode = WrappedPNode(pnode)

converter toIntrp*(intr: WrappedInterpreter): Interpreter = Interpreter(intr)
converter toIntrp*(intr: Interpreter): WrappedInterpreter = WrappedInterpreter(intr)

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
  var errorHook {.exportc: "nimscripter_$1", dynlib.}: ErrorHook
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
      let module = $uProc.module
      if module.len == 0:
        intr.implementRoutine(scriptName, scriptName, $uProc.name, anonProc)
      else:
        intr.implementRoutine(scriptName, module, $uProc.name, anonProc)

when isLib:
  proc load_script(
    script: cstring;
    addins: VMAddins;
    modules: openArray[cstring];
    searchPaths: openArray[cstring];
    stdPath: cstring; 
    defines: openArray[Defines]
  ): WrappedInterpreter {.nimscrintrp.} =

    let
      script = $script
      scriptName = script.splitFile.name
      scriptDir = getTempDir() / scriptName
      scriptNimble = scriptDir / scriptName.changeFileExt(".nimble")
      scriptPath = scriptDir / scriptName.changeFileExt(".nim")

    discard existsOrCreateDir(scriptDir)
    writeFile(scriptNimble, "")

    let scriptFile = open(scriptPath, fmReadWrite)

    var searchPaths = getSearchPath($stdPath) & searchPaths.convertSearchPaths()
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

  proc load_string(
    str: cstring;
    addins: VMAddins;
    modules: openArray[cstring];
    searchPaths: openArray[cstring];
    stdPath: cstring; 
    defines: openArray[Defines]
  ): WrappedInterpreter {.nimscrintrp.} =
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

  proc new_node*(kind: TNodeKind): WrappedPNode {.nimscrintrp.} = ast.newNode(kind)

  proc pnode_add*(node, toAdd: WrappedPNode) {.nimscrintrp.} = PNode(node).add toAdd


  proc int_node*(val: int): WrappedPNode {.nimscrintrp.} = newIntNode(nkIntLit, val.BiggestInt)
  proc int8_node*(val: int8): WrappedPNode {.nimscrintrp.} = newIntNode(nkInt8Lit, val.BiggestInt)
  proc int16_node*(val: int16): WrappedPNode {.nimscrintrp.} = newIntNode(nkInt16Lit, val.BiggestInt)
  proc int32_node*(val: int32): WrappedPNode {.nimscrintrp.} = newIntNode(nkInt32Lit, val.BiggestInt)
  proc int64_node*(val: int64): WrappedPNode {.nimscrintrp.} = newIntNode(nkInt64Lit, val.BiggestInt)

  proc uint_node*(val: uint): WrappedPNode {.nimscrintrp.} = newIntNode(nkuIntLit, val.BiggestInt)
  proc uint8_node*(val: uint8): WrappedPNode {.nimscrintrp.} = newIntNode(nkuInt8Lit, val.BiggestInt)
  proc uint16_node*(val: uint16): WrappedPNode {.nimscrintrp.} = newIntNode(nkuInt16Lit, val.BiggestInt)
  proc uint32_node*(val: uint32): WrappedPNode {.nimscrintrp.} = newIntNode(nkuInt32Lit, val.BiggestInt)
  proc uint64_node*(val: uint64): WrappedPNode {.nimscrintrp.} = newIntNode(nkuInt64Lit, val.BiggestInt)


  proc float_node*(val: float32): WrappedPNode {.nimscrintrp.} = newFloatNode(nkFloat32Lit, val.BiggestFloat)
  proc double_node*(val: float): WrappedPNode {.nimscrintrp.} = newFloatNode(nkFloat64Lit, val.BiggestFloat)

  proc string_node*(val: cstring): WrappedPNode {.nimscrintrp.} = newStrNode(nkStrLit, $val)


  proc pnode_index*(val: WrappedPNode, ind: int): WrappedPNode {.nimscrintrp.} =
    if val.len < ind:
      result = val[ind]

  proc pnode_index_field*(val: WrappedPNode, ind: int): WrappedPNode {.nimscrintrp.} =
    if val.len < ind and val[ind].len == 2:
      result = val[ind][1]

  proc pnode_get_int*(val: WrappedPNode, dest: var BiggestInt): bool {.nimscrintrp.} =
    if PNode(val).kind in {nkCharLit..nkUInt64Lit}:
      result = true
      dest = PNode(val).intVal

  proc pnode_get_double*(val: WrappedPNode, dest: var BiggestFloat): bool {.nimscrintrp.} =
    if PNode(val).kind in {nkFloatLit..nkFloat64Lit}:
      result = true
      dest = PNode(val).floatVal

  proc pnode_get_float*(val: WrappedPNode, dest: var float32): bool {.nimscrintrp.} =
    if PNode(val).kind in {nkFloatLit..nkFloat64Lit}:
      result = true
      dest = float32 PNode(val).floatVal

  proc pnode_get_string*(val: WrappedPNode, dest: var cstring): bool {.nimscrintrp.} =
    if PNode(val).kind in {nkStrLit..nkTripleStrLit}:
      result = true
      dest = cstring PNode(val).strVal

  proc invoke*(intr: WrappedInterpreter, name: cstring, args: openArray[WrappedPNode]): WrappedPNode {.nimscrintrp.} =
    let prcSym = intr.selectRoutine($name)
    if prcSym != nil:
      if args.len == 0:
        result = callRoutine(intr, prcSym, [])
      else:
        let arr = cast[ptr UncheckedArray[PNode]](args[0].addr)
        result = callRoutine(intr, prcSym, arr.toOpenArray(0, args.high))

  proc pnode_get_kind*(node: WrappedPNode): TNodeKind {.nimscrintrp.} = PNode(node).kind

  proc vmargs_get_int*(args: VmArgs, i: Natural): BiggestInt {.nimscrintrp.} = args.getInt(i)
  proc vmargs_get_bool*(args: VmArgs, i: Natural): bool {.nimscrintrp.} = args.getInt(i) != 0
  proc vmargs_get_float*(args: VmArgs, i: Natural): BiggestFloat {.nimscrintrp.} = args.getFloat(i)
  proc vmargs_get_node*(args: VmArgs, i: Natural): WrappedPNode {.nimscrintrp.} = args.getNode(i)
  proc vmargs_get_string*(args: VmArgs, i: Natural): cstring {.nimscrintrp.} = cstring vm.getString(args, i)

  static: # Generate the kind enum
    var str = "enum nimscripter_pnode_kind {"
    for kind in TNodeKind:
      str.add fmt "\n\t{kind} = {ord(kind)}"
      if kind != TNodeKind.high:
        str.add ","
    str.add "};"
    writeFile("tests/lib/nimscr_kinds.h", str)

  proc deinit*() {.nimscrintrp.} = GCfullCollect() # Collect all?


  proc destroy_interpreter*(intr: sink WrappedInterpreter) {.nimscrintrp.} = discard
  proc destroy_pnode*(pnode: sink WrappedPNode) {.nimscrintrp.} = discard


else:
  proc loadScript*(
    script: cstring;
    addins: VMAddins;
    modules: openArray[cstring];
    searchPaths: openArray[cstring];
    stdPath: cstring; 
    defines: openArray[Defines]
  ): WrappedInterpreter {.nimscrintrp, importc: nstr"load_script".}

  proc loadString*(
    script: cstring;
    addins: VMAddins;
    modules: openArray[cstring];
    searchPaths: openArray[cstring];
    stdPath: cstring; 
    defines: openArray[Defines]
  ): WrappedInterpreter {.nimscrintrp, importc: nstr"load_string".}

  proc newNode*(kind: TNodeKind): WrappedPNode {.nimscrintrp, importc: nstr"new_node".}

  proc add*(node, toAdd: WrappedPNode) {.nimscrintrp, importc: nstr"pnode_add".}

  proc newNode*(val: int): WrappedPNode {.nimscrintrp, importc: nstr"int_node".}
  proc newNode*(val: int8): WrappedPNode {.nimscrintrp, importc: nstr"int8_node".}
  proc newNode*(val: int16): WrappedPNode {.nimscrintrp, importc: nstr"int16_node".}
  proc newNode*(val: int32): WrappedPNode {.nimscrintrp, importc: nstr"int32_node".}
  proc newNode*(val: int64): WrappedPNode {.nimscrintrp, importc: nstr"int64_node".}

  proc newNode*(val: uint): WrappedPNode {.nimscrintrp, importc: nstr"uint_node".}
  proc newNode*(val: uint8): WrappedPNode {.nimscrintrp, importc: nstr"uint8_node"}
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

  proc kind*(node: WrappedPNode): TNodeKind {.nimscrintrp, importc: nstr"pnode_get_kind".}

  proc getInt*(args: VmArgs, i: Natural): BiggestInt {.nimscrintrp, importc: nstr"vmargs_get_int".}
  proc getBool*(args: VmArgs, i: Natural): bool {.nimscrintrp, importc: nstr"vmargs_get_bool".}
  proc getFloat*(args: VmArgs, i: Natural): BiggestFloat {.nimscrintrp, importc: nstr"vmargs_get_float".}
  proc getNode*(args: VmArgs, i: Natural): WrappedPNode {.nimscrintrp, importc: nstr"vmargs_get_node".}
  proc getString*(args: VmArgs, i: Natural): cstring {.nimscrintrp, importc: nstr"vmargs_get_string".} 

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
