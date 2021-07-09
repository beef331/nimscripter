import std/[macros, macrocache]
import compiler/[renderer, ast, vmdef, vm]
import marshalns, procsignature
export VmProcSignature, marshalns

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

func getVmRuntimeImpl(pDef: NimNode): string =
  ## Returns the nimscript code that will convert to string and return the value.
  ## This does the interop and where we want a serializer if we ever can.
  let
    deSymd = deSym(pDef.copyNimTree())
    data = genSym(nskVar, "data")
    mangledProc = ident(getMangledName(pdef))
    hasParams = pDef.params.len > 1
    hasRetVal = pdef.params[0].kind != nnkEmpty

  if hasParams:
    deSymd[^2] = newStmtList()
    deSymd[^2].add quote do:
      var `data` = ""
    for def in pDef.params[1..^1]:
      for idnt in def[0..^3]: # Get data from buffer in the vm proc
        let idnt = ident($idnt)
        deSymd[^2].add quote do:
          addToBuffer(`idnt`, `data`)

  if hasRetVal:
    let
      retT = pdef.params[0]
      pos = genSym(nskVar, "pos")
    if hasParams: # Call the proc with "args"
      deSymd[^2].add quote do:
        var `pos`: BiggestInt
        result = getFromBuffer[`retT`](`mangledProc`(`data`), `pos`)
    else: # Just call the proc
      deSymd[^2].add quote do:
        var `pos`: BiggestInt
        result = getFromBuffer[`retT`](`mangledProc`(), `pos`)
  else:
    if hasParams: # Call proc with "Args"
      deSymd[^2].add quote do:
        result = `mangledProc`(`data`)
    else: # Just call the proc
      deSymd[^2].add quote do:
        `mangledProc`()
  result = deSymd.repr



proc getLambda(pDef: NimNode): NimNode =
  ## Generates the lambda for the vm backed logic.
  ## This is what the vm calls internally when talking to Nim
  let
    vmArgs = ident"vmArgs"
    args = ident"args"
    pos = ident"pos"
    tmp =
      if pDef.params.len > 1:
        quote do:
          proc n(`vmArgs`: VmArgs){.closure, gcsafe.} =
            var `pos`: BiggestInt = 0
            let `args` = getString(`vmArgs`, 0)
      else:
        quote do:
          proc n(`vmArgs`: VmArgs){.closure, gcsafe.} = discard

  if tmp[^1].kind == nnkDiscardStmt: # Replace discard so we can write here
    tmp[^1] = newStmtList()

  tmp[0] = newEmptyNode()
  result = nnkLambda.newNimNode()
  tmp.copyChildrenTo(result)

  var procArgs: seq[NimNode]
  for def in pDef.params[1..^1]:
    let typ = def[^2]
    for idnt in def[0..^3]: # Get data from buffer in the vm proc
      let idnt = ident($idnt)
      procArgs.add idnt
      result[^1].add quote do:
        var `idnt` = getFromBuffer[`typ`](`args`, `pos`)

  if pDef.params[0].kind == nnkEmpty: # If we dont have return type just call
    result[^1].add newCall(pDef[0], procArgs)
  else: # Else we have to return this to the vm
    let procCall = newCall(pDef[0], procArgs)
    result[^1].add quote do:
      var data: string = ""
      `procCall`.addToBuffer(data)
      `vmArgs`.setResult(data)


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
