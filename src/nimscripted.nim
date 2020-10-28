import macros
import vmtable
import marshalns
export marshalns

macro exportToScript*(input: untyped): untyped=
  let 
    rtnType = input[3][0]
    hasRtnVal = rtnType.kind != nnkEmpty
    argIdent = ident("args")
    buffIdent = ident("buff")
    posIdent = ident("pos")
  var
    params: seq[NimNode]
    vmBody = newStmtList().add quote do:
      var 
        `buffIdent` = `argIdent`.getString(0)
        `posIdent`: BiggestInt = 0
    nameMangling = "" #Easiest way for the comp name
  for identDefs in input[3][1..^1]:
    let idType = ident($identDefs[^2])
    for param in identDefs[0..^3]:
      params.add param
      nameMangling.add($param)
      vmBody.add quote do:
        let `param` = getFromBuffer(`buffIdent`, `idType`, `posIdent`)
  let 
    procName = input[0]

  if hasRtnVal:
    vmBody.add quote do:
      var data = ""
      `procName`().addToBuffer(data)
      `argIdent`.setResult(data)
    vmBody[^1][1][0][0].add(params)
  else:
    vmBody.add quote do:
      `procName`()
    vmBody[^1].add(params)

  let vmCompName = ident(($input[0]) & nameMangling)

  var
    vmRuntime = copy(input)
    vmComp = copy(input)
  vmComp[0] = vmCompName
  if vmComp[3].len > 2:
    vmComp[3].del(2, vmComp[3].len - 2)
  if vmComp[3].len > 1:
    vmComp[3][1] = newIdentDefs(ident("parameters"), ident("string"))
  if hasRtnVal:
    vmComp[3][0] = ident("string")
  vmComp[6] = quote do:
    discard
  
  var conversion = newStmtList()
  if params.len > 0:
    let paramsIdent = ident("params")
    conversion.add quote do:
      var `paramsIdent` = ""
    for param in params:
      conversion.add quote do:
        addToBuffer(`param`, `paramsIdent`)
  else: conversion = newEmptyNode()

  if hasRtnVal:
    vmRuntime[6] = quote do:
      `conversion`
      var returnVal = ""
      `vmCompName`().addToBuffer(returnVal)
      args.setResult(returnVal)
  else:
    vmRuntime[6] = quote do:
      `conversion`
      `vmCompName`(params)
  let
    compDefine = $vmComp.repr
    runtimeDefine = $vmRuntime.repr
    compName = newStrLitNode($vmCompName)
    runName = newStrLitNode($input[0])
    constr = quote do:
      static:
        scriptedTable.add(VmProcSignature(vmCompDefine: `compDefine`, vmRunDefine: `runtimeDefine`, name: `runName`, compName: `compName`, vmProc: proc(`argIdent`: VmArgs)= `vmBody`))
  result = newStmtList().add(input, constr)
  echo vmRuntime.repr
  echo vmComp.repr
  echo vmBody.repr
type Test = object
  x, y: float

proc test(a: int, b: float, c: string, t: Test) {.exportToScript.} = 
  echo a
  echo b
  echo c
  echo t
