import std/macros
import common

func getVmRuntimeImpl*(pDef: NimNode): string =
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