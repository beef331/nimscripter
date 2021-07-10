import std/[json, macros]
import common
export json
func getVmRuntimeImpl*(pDef: NimNode): string =
  ## Returns the nimscript code that will convert to string and return the value.
  ## This does the interop and where we want a serializer if we ever can.
  let
    deSymd = deSym(pDef.copyNimTree())
    mangledProc = ident(getMangledName(pdef))
    hasParams = pDef.params.len > 1
    hasRetVal = pdef.params[0].kind != nnkEmpty
    tupleNames = nnkTupleConstr.newNimNode()
  
  deSymd[^2] = newStmtList()
  if hasParams:
    for def in pDef.params[1..^1]:
      for idnt in def[0..^3]: # Get data from buffer in the vm proc
        let name = ident($idnt)
        tupleNames.add name

  let retT = pdef.params[0]

  if hasRetVal:
    if hasParams: # Call the proc with "args"
      deSymd[^2].add quote do:
        result = to(`mangledProc`(%* `tupleNames`).parseJson `retT`)
    else: # Just call the proc
      deSymd[^2].add quote do:
        result = to(`mangledProc`().parseJson `retT`)
  else:
    if hasParams: # Call proc with "Args"
      deSymd[^2].add quote do:
        result = to(`mangledProc`(%* `tupleNames`).parseJson `retT`)
    else: # Just call the proc
      deSymd[^2].add quote do:
        `mangledProc`()

  result = deSymd.repr



proc getLambda*(pDef: NimNode): NimNode =
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
  let
    tupleNames = nnkVarTuple.newNimNode()
    tupleType = nnkTupleTy.newNimNode()
  for def in pDef.params[1..^1]:
    let typ = def[^2]
    for idnt in def[0..^3]: # Get data from buffer in the vm proc
      let idnt = ident($idnt)
      tupleNames.add idnt
      tupleType.add newIdentDefs(idnt, typ, newEmptyNode())
      procArgs.add idnt

  if tupleNames.len > 0:
    tupleNames.add newEmptyNode()
    tupleNames.add newCall(ident"to", newCall("parseJson", args), tupleType)
    result[^1].add nnkLetSection.newTree(tupleNames)

  if pDef.params[0].kind == nnkEmpty: # If we dont have return type just call
    result[^1].add newCall(pDef[0], procArgs)
  else: # Else we have to return this to the vm
    let procCall = newCall(pDef[0], procArgs)
    result[^1].add quote do:
      var data: string = ""
      `vmArgs`.setResult($(%* `procCall`))
  echo result.repr