import macros
import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm]
import sets
import strutils
import vmtable
export VmArgs, nimeval, renderer, ast, types, llstream, vmdef, vm
import marshalns
export marshalns, VmArgs, getString, getFloat, getInt, Interpreter

macro exportToScript*(input: untyped): untyped=
  let 
    rtnType = input[3][0]
    hasRtnVal = rtnType.kind != nnkEmpty
    argIdent = ident("args")
    buffIdent = ident("buff")
    posIdent = ident("pos")
  var
    params: seq[NimNode]
    vmBody = newStmtList()
    nameMangling = "" #Easiest way for the comp name
  
  #Only get params if we have them
  if input[3].len > 1: vmBody.add quote do:
      var 
        `buffIdent` = `argIdent`.getString(0)
        `posIdent`: BiggestInt = 0

  for identDefs in input[3][1..^1]:
    let idType = ident($identDefs[^2])
    if identDefs[^2].kind == nnkIdent:
      nameMangling &= ($identDefs[^2])[0] & ($identDefs[^2])[^1]
    for param in identDefs[0..^3]:
      params.add param
      nameMangling.add($param)
      vmBody.add quote do:
        let `param` = getFromBuffer(`buffIdent`, `idType`, `posIdent`)
  let 
    procName = if input[0].kind == nnkPostfix: input[0].basename else: input[0]
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

  let vmCompName = ident(($procName) & "Comp" & nameMangling)

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

  let 
    rtnbufIdent = ident("returnBuf")
  if hasRtnVal:
    vmRuntime[6] = quote do:
      `conversion`
      var 
        `rtnbufIdent` = ""
        `posIdent`: BiggestInt = 0
      `vmCompName`().getFromBuffer(`rtnType`, `posIdent`)
    if input[3].len > 1:
      vmRuntime[^1][^1][0][0].add(ident("params"))
  else:
    vmRuntime[6] = quote do:
      `conversion`
      `vmCompName`()
    if input[3].len > 1:
      vmRuntime[^1][^1].add(ident("params"))
  let
    compDefine = $vmComp.repr
    runtimeDefine = $vmRuntime.repr
    compName = newStrLitNode($vmCompName)
    runName = newStrLitNode($procName)
    constr = quote do:
      static:
        scriptedTable.add(VmProcSignature(vmCompDefine: `compDefine`, vmRunDefine: `runtimeDefine`, name: `runName`, compName: `compName`, vmProc: proc(`argIdent`: VmArgs){.closure, gcsafe.}= `vmBody`))
  result = newStmtList().add(input, constr)

macro exportCode*(typeSect: untyped): untyped=
  let a = newStrLitNode($typeSect.repr)
  typeSect.add quote do:
    static:
      exportedCode.add `a`
  result = typeSect