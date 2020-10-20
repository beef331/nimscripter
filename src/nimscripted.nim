import macros
import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm]
import sets
import strutils
import vmtable
import json
export VmArgs, nimeval, renderer, ast, types, llstream, vmdef, vm, json

macro exportToScript*(input: untyped): untyped=
  when not defined(scripted): return input
  var
    runTimeArgs: seq[NimNode]
    argIdents: seq[NimNode]

  for x in input[3]:
    if x.kind == nnkIdentDefs:
      runTimeArgs.add x
      argIdents.add x[0..<(^2)]

  let hasRtnVal = input[3][0].kind != nnkEmpty

  let duplicated = copyNimTree(input)
  duplicated[^1] = newNimNode(nnkDiscardStmt).add(newEmptyNode()) #Replace body with discard for a placeholder
  
  if input[3].len > 1:
    duplicated[3] = newNimNode(nnkFormalParams).add(@[newEmptyNode(), newIdentDefs(ident("data"), ident("string"))])
    if hasRtnVal:
      duplicated[3][0] = ident("string")
  elif hasRtnVal:
    duplicated[3] = newNimNode(nnkFormalParams).add(ident("string"))
  
  var disrupteksAnger: string
  for ide in argIdents:
    disrupteksAnger.add ($ide)[0]
    disrupteksAnger.add ($ide)[^1]
  for arg in runTimeArgs:
    if arg[^2].kind != nnkEmpty:
      disrupteksAnger.add ($arg[^2])[0]
      disrupteksAnger.add ($arg[^2])[^1]

  let
    name = ($input[0]).replace("*")
    compileName = name & "Comp" & disrupteksAnger
  var
    vmCompDefine = ($duplicated.repr).replace(name, compileName) #Make it procNameComp(args)
    args = ident("args")
    vmRuntimeProc = copyNimTree(input)
  
  #Call the injected proc from nimscript
  let 
    returnType = input[3][0]
    data = ident("data")
  var 
    i = 0
    #Base to hold all the conversion
    conversion = newStmtList().add quote do:
      let `data` = newJObject()
  #For each parameter convert to jsonnode
  for param in runTimeArgs:
    for p in param[0..<(^2)]:
      var 
        paramName = newStrLitNode("param" & $i)
      conversion.add quote do:
        `data`[`paramName`] = %*`p`
      inc i

  if runTimeArgs.len > 0:
    vmRuntimeProc[^1] = newCall(ident(compileName), prefix(data, "$"))
  else:
    vmRuntimeProc[^1] = newCall(ident(compileName), newEmptyNode())
  let runtimeProc = vmRuntimeProc[^1]

  #If it has a return value and it's not primitve convert from json
  if hasRtnVal:
    vmRuntimeProc[^1] = quote do:
      `conversion`
      parseJson(`runtimeProc`)["result"].to(`returnType`)
  else:
    vmRuntimeProc[^1] = quote do:
      `conversion`
      `runtimeProc`
  let 
    vmRuntimeDefine = $vmRuntimeProc.repr #We're just using the nim AST to generate the nimscript proc
    jsonData = ident("jsonData")
  #All parameters are stored in json in a `paramIndex` notation
  var vmBody = newStmtList().add quote do:
      let `jsonData` = `args`.getString(0).parseJson()

  var 
    callArgs: seq[NimNode]
  i = 0
  #For each parameter convert to the type
  for param in runTimeArgs:
    let pType = param[^2]
    for p in param[0..<(^2)]:
      var 
        paramName = ident("param" & $i)
        paramStr = newStrLitNode("param" & $i)
      callArgs.add(paramName)
      vmBody.add quote do:
        let `paramName` = `jsonData`[`paramStr`].to(`pType`)
      inc i
  let compNameIdent = newStrLitNode(compileName)
  result = newStmtList(input,
  quote do:
    static: scriptedTable.add(VmProcSignature(vmCompDefine: `vmCompDefine`, compName: `compNameIdent`,  vmRunDefine: `vmRuntimeDefine`, name: `name`, vmProc: 
    proc(`args`: VmArgs){.closure, gcsafe.}= discard))
  )
  let objConst = result[1][0][0][1]
  vmBody.add newCall(input[0].basename, callArgs)
  if hasRtnVal:
    let call = newCall(input[0].basename, callArgs)
    vmBody[^1] = quote do:
      `args`.setResult($ %*{"result": `call`})
  objConst[5][1][6] = vmBody #Set the vmproc body from discard to the proper parsing/calling
