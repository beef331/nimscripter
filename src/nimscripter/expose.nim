import std/[macros, macrocache]
import compiler/[renderer, ast, vmdef, vm]
import marshalns, procsignature
import private/common
export VmProcSignature, marshalns

when defined(jsoninterop):
  import private/jsoninterop
  export json
else:
  import private/bininterop

const
  procedureCache = CacheTable"NimscriptProcedures"
  codeCache = CacheTable"NimscriptCode"

macro exportToScript*(moduleName: untyped, procedure: typed): untyped =
  result = procedure
  moduleName.expectKind(nnkIdent)
  block add:
    for name, _ in procedureCache:
      if name == $moduleName:
        procedureCache[name].add procedure
        break add
    procedureCache[$moduleName] = nnkStmtList.newTree(procedure)

func deSym(n: NimNode): NimNode =
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

func getVmStringImpl(pDef: NimNode): string =
  ## Takes a proc and changes the name to be manged for the string backend
  ## parameters are replaced with a single string, return value aswell.
  ## Hidden backed procedure for the Nim interop
  let deSymd = deSym(pdef.copyNimTree())
  deSymd[0] = ident(getMangledName(pDef))

  if deSymd.params.len > 2: # Delete all params but first/return type
    deSymd.params.del(2, deSymd[3].len - 2)

  if deSymd.params.len > 1: # Changes the first parameter to string named `parameters`
    deSymd.params[1] = newIdentDefs(ident("parameters"), ident("string"))

  if deSymd.params[0].kind != nnkEmpty: # Change the return type to string so can be picked up later
    deSymd.params[0] = ident("string")

  deSymd[^1] = nnkDiscardStmt.newTree(newEmptyNode())
  deSymd[^2] = nnkDiscardStmt.newTree(newEmptyNode())
  result = deSymd.repr

macro implNimscriptModule*(moduleName: untyped): untyped =
  moduleName.expectKind(nnkIdent)
  result = nnkBracket.newNimNode()
  for p in procedureCache[$moduleName]:
    let
      stringImpl = getVmStringImpl(p)
      runImpl = getVmRuntimeImpl(p)
      lambda = getLambda(p)
      mangledName = getMangledName(p)
      realName = $p[0]
    result.add quote do:
      VmProcSignature(
        vmStringImpl: `stringImpl`,
        vmStringName: `mangledName`,
        vmRunImpl: `runImpl`,
        realName: `realName`,
        vmProc: `lambda`
      )
