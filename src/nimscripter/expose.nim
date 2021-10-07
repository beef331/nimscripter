import std/[macros, macrocache, typetraits, strutils]
import compiler/[vmdef, vm, ast]
import vmconversion

import procsignature
export VmProcSignature

var genSymOffset {.compileTime.} = 321321

proc genSym(name: string): NimNode =
  result = ident(name & $genSymOffset)
  inc genSymOffset

func deSym*(n: NimNode): NimNode =
  # Remove all symbols
  result = n
  for x in 0 .. result.len - 1:
    if result[x].kind == nnkSym:
      result[x] = ident($result[x])
    else:
      result[x] = result[x].deSym

func getMangledName*(pDef: NimNode): string =
  ## Generates a close to type safe name for backers
  result = $pdef[0]
  for def in pDef[3][1..^1]:
    for idnt in def[0..^3]:
      result.add $idnt
    if def[^2].kind in {nnkSym, nnkIdent}:
      result.add $def[^2]
  result.add "Comp"

func getVmRuntimeImpl*(pDef: NimNode): string =
  ## Returns the nimscript code that will convert to string and return the value.
  ## This does the interop and where we want a serializer if we ever can.
  let deSymd = deSym(pDef.copyNimTree())
  deSymd[^1] = nnkDiscardStmt.newTree(newEmptyNode())
  deSymd[^2] = nnkDiscardStmt.newTree(newEmptyNode())
  deSymd[2] = newEmptyNode()
  for i, x in deSymd.params[1..^1]:
    if x[^2].typeKind == ntyOr:
      deSymd.params[i + 1][^2] = x[^2][1]
  deSymd.repr

proc getReg(vmargs: Vmargs, pos: int): TFullReg = vmargs.slots[pos + vmargs.rb + 1]

proc getLambda*(pDef: NimNode, realProcName: Nimnode = nil): NimNode =
  ## Generates the lambda for the vm backed logic.
  ## This is what the vm calls internally when talking to Nim
  let
    vmArgs = ident"vmArgs"
    tmp = quote do:
      proc n(`vmArgs`: VmArgs){.closure, gcsafe.} = discard

  tmp[^1] = newStmtList()

  tmp[0] = newEmptyNode()
  result = nnkLambda.newNimNode()
  tmp.copyChildrenTo(result)

  var procArgs: seq[NimNode]
  for i, def in pDef.params[1..^1]:
    var typ = def[^2]
    case typ.typeKind
    of ntyOr:
     typ = typ[1]
    of ntyBuiltinTypeClass, ntyCompositeTypeClass:
      error("Cannot use type classes with nimscripter, make an alias.", pdef)
    elif typ.kind == nnkEmpty: 
     typ = newCall("typeof", def[^1])
    else: discard
    for idnt in def[0..^3]: # Get data from buffer in the vm proc
      let
        idnt = ident($idnt)
        argNum = newLit(procArgs.len)
      procArgs.add idnt
      result[^1].add quote do:
        let reg = getReg(`vmArgs`, `argNum`)
        var `idnt`: `typ`
        when `typ` is (SomeOrdinal or enum):
          case reg.kind:
          of rkInt:
            `idnt` = `typ`(reg.intVal)
          of rkNode:
            `idnt` = fromVm(typeof(`typ`), reg.node)
          else: discard
        elif `typ` is SomeFloat:
          case reg.kind:
          of rkFloat:
            `idnt` = `typ`(reg.floatVal)
          of rkNode:
            `idnt` = fromVm(typeof(`typ`), reg.node)
          else: discard
        else:
          `idnt` = fromVm(typeof(`typ`), getNode(`vmArgs`, `argNum`))

  let procName = 
    if realProcName != nil:
      realProcName
    else:
      pDef[0]

  if pdef.params.len > 1:
    result[^1].add newCall(procName, procArgs)
  else:
    result[^1].add newCall(procName)
  if pdef.params[0].kind != nnkEmpty:
    let
      retT = pDef.params[0]
      call = result[^1][^1]
    result[^1][^1] = quote do:
      when `retT` is (SomeOrdinal or enum):
        `vmArgs`.setResult(BiggestInt(`call`))
      elif `retT` is SomeFloat:
        `vmArgs`.setResult(BiggestFloat(`call`))
      elif `retT` is string:
        `vmArgs`.setResult(`call`)
      else:
        `vmArgs`.setResult(toVm(`call`))

const
  procedureCache = CacheTable"NimscriptProcedures"
  addonsCache = CacheTable"NimscriptAddons"

proc addToProcCache(n: NimNode, moduleName: string) =
  var impl: NimNode
  if n.kind == nnkProcDef:
    impl = n
  elif n.kind == nnkSym and n.symKind in {nskProc, nskFunc}:
    impl = n.getImpl
  elif n.kind == nnkSym and n.symKind in {nskVar, nskLet, nskConst}:
    impl = n
  else: 
    impl = n
  for name, _ in procedureCache:
    if name == moduleName:
      procedureCache[name].add n
      return
  procedureCache[moduleName] = nnkStmtList.newTree(n)

proc addToAddonCache(n: NimNode, moduleName: string) =
  var impl = n.getImpl()
  if impl.kind == nnktypeDef:
    impl = nnkTypeSection.newTree(impl)
  for name, _ in addonsCache:
    if name == moduleName:
      addonsCache[name].add impl
      return
  addonsCache[moduleName] = nnkStmtList.newTree(impl)

macro addToCache*(sym: typed, moduleName: static string) =
  if sym.kind == nnkSym and sym.symKind in {nskType, nskConverter, nskIterator, nskMacro}:
    addToAddonCache(sym, moduleName)
  else:
    addToProcCache(sym, moduleName)

macro exportTo*(moduleName: untyped, procDefs: varargs[untyped]): untyped =
  result = newStmtList()
  var moduleName = $moduleName
  for pDef in procDefs:
    result.add newCall("addToCache", pdef, newLit(modulename))

iterator generateParamHeaders(paramList: NimNode, types: seq[(int, NimNode)], indicies: var seq[int]): NimNode =
  var params = copyNimTree(paramList)
  while indicies[^1] < (types[^1][1].len - 1):
    for x in 0..types.high:
      let
        (ind, typ) = types[x]
      params[ind][^2] = typ[indicies[x] + 1]
    yield params
    inc indicies[0]
    for i, x in indicies:
      if indicies[i] >= types[i][1].len - 1:
        if i + 1 < indicies.len:
          inc indicies[i + 1]
          indicies[i] = 0

proc makeVMProcSignature(n: NimNode, genSym = false): NimNode =
  if not genSym:
    n[4] = newEmptyNode() # remove pragmas
    n[^2] = newStmtList() # remove bodies
    n[^1] = newStmtList() # remove bodies
    let
      runImpl = getVmRuntimeImpl(n)
      lambda = getLambda(n)
      realName = $n[0]
    result = quote do:
      VmProcSignature(
        name: `realName`,
        vmRunImpl: `runImpl`,
        vmProc: `lambda`
      )
  else:
    # This is gensym'd so there is a proc calling a hidden proc,
    # since the VM doesnt support overload implementations
    let
      newDef = copyNimTree(n)
      newName = genSym($n[0])
      strName = $newName
    newDef[0] = newName
    newDef[4] = newEmptyNode() # Remove pragmas
    newDef[^1] = newStmtList() # Removes body
    newDef[^2] = newStmtList() # Removes body

    var runImpl = getVmRuntimeImpl(newDef)
    let lambda = getLambda(n)
    newDef[0] = n[0]
    newDef[^1] = newCall(newName)
    newDef[^2] = newCall(newName)

    for i, def in n.params:
      if i > 0:
        # Body can be in one of two places
        newDef[^1].add def[0..^3]
        newDef[^2].add def[0..^3]
    runImpl.add newDef.repr
    result = quote do:
      VmProcSignature(
        name: `strName`,
        vmRunImpl: `runImpl`,
        vmProc: `lambda`
      )


proc generateTypeclassProcSignatures(pDef: Nimnode): NimNode =
  result = newStmtList()
  var
    types: seq[(int, NimNode)]
    indicies: seq[int]
  for i in 1..<pdef.params.len:
    if pDef.params[i][^2].typeKind == ntyOr:
      types.add (i, pdef.params[i][^2])
      indicies.add 0
  for params in generateParamHeaders(pDef.params, types, indicies):
    let newDef = pdef.copyNimTree
    newDef[3] = params
    result.add makeVMProcSignature(newDef, true)

proc generateModuleImpl(n: NimNode, genSym = false): NimNode =
  case n.kind
    of nnkProcDef, nnkFuncDef:
      if n[2].len == 0:
        # is not a generic proc dont need anything special
        result = makeVMProcSignature(n, genSym)
      else:
        result = generateTypeclassProcSignatures(n):
    of nnkSym:
      if n.symKind in {nskProc, nskFunc}:
        result = generateModuleImpl(n.getImpl, genSym)
      elif n.symKind in {nskVar, nskLet, nskConst}:
        let
          procName = genSym($n)
          strName = $procName
          typ = getType(n)
          realName = n
          runCode = quote:
            proc `procName`(): `typ` = discard
            template `realName`: `typ` = `procName`()
          runImpl = runcode.repr
        result = quote do:
          VmProcSignature(
              name: `strName`,
              vmRunImpl: `runImpl`,
              vmProc: proc(vmArgs: VmArgs){.gcsafe.} =
                when `typ` is (SomeOrdinal or enum):
                  vmArgs.setResult(`n`.BiggestInt)
                elif `typ` is SomeFloat:
                  vmArgs.setResult(`n`.BiggestFloat)
                elif `typ` is string:
                  vmargs.setResult(`n`)
                else:
                  vmArgs.setResult(toVm(`n`))
            )
    of nnkClosedSymChoice:
      result = newStmtList()
      for impl in n:
        let impls = generateModuleImpl(impl, true) 
        if impls.kind == nnkStmtList:
          for impl in impls:
            result.add impl
        else:
          result.add impls
    else: error("Some bug: " & $n.kind, n)


macro implNimscriptModule*(moduleName: untyped): untyped =
  moduleName.expectKind(nnkIdent)
  result = nnkBracket.newNimNode()
  for p in procedureCache[$moduleName]:
    let impl = generateModuleImpl(p)
    if impl.kind == nnkStmtList:
      for child in impl:
        result.add child
    else:
      result.add impl
  var addons = ""
  for (key, val) in addonsCache.pairs:
    if modulename.eqIdent(key):
      for impl in val:
        addons.add impl.repr
        addons.setLen(addons.rfind('\n') + 1) # removes indentations
  if addons.len > 0:
    result = nnkTupleConstr.newTree(result, newLit(addons))