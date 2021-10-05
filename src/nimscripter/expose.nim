import std/[macros, macrocache, typetraits]
import compiler/[vmdef, vm, ast]
import vmconversion

import procsignature
export VmProcSignature

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

const procedureCache = CacheTable"NimscriptProcedures"

proc addToCache(n: NimNode, moduleName: string) = 
  for name, _ in procedureCache:
    if name == moduleName:
      procedureCache[name].add n
      return
  procedureCache[moduleName] = nnkStmtList.newTree(n)

macro exportToScript*(moduleName: untyped, procedure: typed): untyped =
  result = procedure
  if procedure.kind == nnkProcDef:
    addToCache(procedure, $moduleName)
  else:
    error("Use `exportTo` for block definitions, `exportToScript` is for proc defs only", procedure)

macro exportTo*(moduleName: untyped, procDefs: varargs[typed]): untyped =
  for pDef in procDefs:
    if pdef.kind == nnkProcDef:
      addToCache(pDef, $moduleName)
    elif pdef.kind == nnkSym and pdef.symKind in {nskProc, nskFunc}:
      addToCache(pdef.getImpl, $moduleName)
    else:
      error("Invalid procdef", pdef)

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
    var procName = $pdef[0]
    let newDef = pdef.copyNimTree
    for i, x in params:
      if i > 0:
        procname.add(x[^2].repr)
    echo procName
    let
      realName = ident(procName)
      strName = newLit($procName)

    newDef[0] = realName
    newDef[3] = params
    
    var runImpl = getVmRuntimeImpl(newDef)
    let
      lambda = getLambda(newDef, pdef[0])
    newDef[0] = pdef[0]
    newDef[^1] = newCall(realName)

    for i, def in pdef.params:
      if i > 0:
        for ident in def[0..^3]:
          newDef[^1].add ident
    runImpl.add newDef.repr

    result.add quote do:
      VmProcSignature(
        name: `strName`,
        vmRunImpl: `runImpl`,
        vmProc: `lambda`
      )
  echo result.repr


macro implNimscriptModule*(moduleName: untyped): untyped =
  moduleName.expectKind(nnkIdent)
  result = nnkBracket.newNimNode()
  for p in procedureCache[$moduleName]:
    if p[2].len == 0: 
      # is not a generic proc dont need anything special
      let
        runImpl = getVmRuntimeImpl(p)
        lambda = getLambda(p)
        realName = $p[0]
      result.add quote do:
        VmProcSignature(
          name: `realName`,
          vmRunImpl: `runImpl`,
          vmProc: `lambda`
        )
    else:
      for x in generateTypeclassProcSignatures(p):
        result.add x
