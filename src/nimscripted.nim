import macros
import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm]
import sets
import strutils
import vmtable
export VmArgs, nimeval, renderer, ast, types, llstream, vmdef, vm
import marshalns
export marshalns, VmArgs, getString, getFloat, getInt, Interpreter

proc exposeProc(input: NimNode): NimNode=
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

  #Foreach parameter we use it's name to generate some mangling to remove proc overlap
  for identDefs in input[3][1..^1]:
    let idType = ident($identDefs[^2])
    if identDefs[^2].kind == nnkIdent:
      nameMangling &= ($identDefs[^2])[0] & ($identDefs[^2])[^1]
    for param in identDefs[0..^3]:
      params.add param
      nameMangling.add($param)
      #Code to extract data directly from the string
      vmBody.add quote do:
        let `param` = getFromBuffer(`buffIdent`, `idType`, `posIdent`)
  let 
    procName = if input[0].kind == nnkPostfix: input[0].basename else: input[0]
  #If we have a return value we set result of the Vmargs
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

  #Our mangled name, bless disruptek's heart
  let vmCompName = ident(($procName) & "Comp" & nameMangling)

  #We're abusing Nim's AST generation to make usable code for the VM
  var
    vmRuntime = copy(input)
    vmComp = copy(input)
  vmComp[0] = vmCompName
  #If we have more than 1 argument def, remove them as we just need `procName`(params: string): string
  if vmComp[3].len > 2:
    vmComp[3].del(2, vmComp[3].len - 2)
  #If we have any parameters replace it with a string named "parameters"
  if vmComp[3].len > 1:
    vmComp[3][1] = newIdentDefs(ident("parameters"), ident("string"))
  #We always return data as a binary string
  if hasRtnVal:
    vmComp[3][0] = ident("string")
  vmComp[6] = quote do:
    discard
  
  var conversion = newStmtList()
  #[
    When when we have parameters we need to add them
    to a string buffer to send to nim
  ]#
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
    #We need to extract the return value from the proc call
    vmRuntime[6] = quote do:
      `conversion`
      var 
        `rtnbufIdent` = ""
        `posIdent`: BiggestInt = 0
      `vmCompName`().getFromBuffer(`rtnType`, `posIdent`)
    if input[3].len > 1:
      vmRuntime[^1][^1][0][0].add(ident("params"))
  else:
    #We just need to call the proc
    vmRuntime[6] = quote do:
      `conversion`
      `vmCompName`()
    if input[3].len > 1:
      vmRuntime[^1][^1].add(ident("params"))

  #Make all of our finalized data
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

macro exportToScript*(input: untyped): untyped =
  if input.kind == nnkProcDef:
    result = input.exposeProc
  else:
    for i in 0..<input.len:
      var node = input[i]
      if node.kind == nnkProcDef:
        input[i] = node.exposeProc
    result = input