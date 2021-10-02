import std/[macros, macrocache, typetraits]
import compiler/[vmdef, vm]
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
  deSymd.repr


proc getLambda*(pDef: NimNode): NimNode =
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
  for def in pDef.params[1..^1]:
    let typ = def[^2]
    for idnt in def[0..^3]: # Get data from buffer in the vm proc
      let
        idnt = ident($idnt)
        argNum = newLit(procArgs.len)
      procArgs.add idnt
      result[^1].add quote do:
        var `idnt` = fromVm(typeof(`typ`), getNode(`vmArgs`, `argNum`))
  if pdef.params.len > 1:
    result[^1].add newCall(pDef[0], procArgs)

const procedureCache = CacheTable"NimscriptProcedures"

macro exportToScript*(moduleName: untyped, procedure: typed): untyped =
  result = procedure
  moduleName.expectKind(nnkIdent)
  block add:
    for name, _ in procedureCache:
      if name == $moduleName:
        procedureCache[name].add procedure
        break add
    procedureCache[$moduleName] = nnkStmtList.newTree(procedure)

macro implNimscriptModule*(moduleName: untyped): untyped =
  moduleName.expectKind(nnkIdent)
  result = nnkBracket.newNimNode()
  for p in procedureCache[$moduleName]:
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

