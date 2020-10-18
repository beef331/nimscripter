import macros
import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm]
import sets
import strutils
import vmtable
export VmArgs, nimeval, renderer, ast, types, llstream, vmdef, vm

const 
  intNames = ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "byte", "uint16", "uint32", "uint64"].toHashSet
  floatNames = ["float32", "float", "float64"].toHashSet

proc isPrimitive(str: string): bool = str in intNames + floatNames + ["bool", "string"].toHashSet

{.experimental: "dynamicBindSym".} 

macro scripted*(input: untyped): untyped=
  var 
    paramTypes: seq[NimNode]
    runTimeArgs: seq[NimNode]
  for x in input[3]:
    if x.kind == nnkIdentDefs:
      #For each declared variable here
      for declared in 0..<(x.len-2):
        #If it's not a primitive convert to json, else just send it
        let
          xSym = x[^2].bindSym
          xType = xSym.getImpl()
          isAlias = (xType.kind == nnkTypeDef and xType[^1].kind == nnkSym and ($xType[^1]).isPrimitive)
        paramTypes.add x[^2]
        if not isAlias and (x[^2].kind == nnkIdent and not ($x[^2]).isPrimitive):
          runTimeArgs.add newNimNode(nnkPrefix).add(ident("$"),newNimNode(nnkPrefix).add(ident("%"), x[declared]))
        else: runTimeArgs.add x[declared]

  let hasRtnVal = input[3][0].kind != nnkEmpty

  let duplicated = copyNimTree(input)
  duplicated[^1] = newNimNode(nnkDiscardStmt).add(newEmptyNode()) #Replace body with discard for a placeholder

  var 
    name = ($input[0]).replace("*")
    vmCompDefine = ($duplicated.repr).replace(name, name & "Comp") #Make it procNameComp(args)
    args = ident("args")
    vmRuntimeProc = copyNimTree(input)
    procArgs: seq[NimNode]
    objectConversion: seq[NimNode]
  #Call the injected proc from nimscript
  vmRuntimeProc[^1] = newCall(ident(name & "Comp"), runTimeArgs)
  #If it has a return value and it's not primitve convert from json
  if input[3][0].kind == nnkIdent:
    let
      xSym = input[3][0].bindSym 
      xType = xSym.getImpl()
      isAlias = (xType[^1].kind == nnkSym and ($xType[^1]).isPrimitive)
    if isAlias or (hasRtnVal and not ($input[3][0]).isPrimitive):
      vmRuntimeProc[^1] = newCall(ident("to"),newCall(ident("parseJson"),vmRuntimeProc[^1]), input[3][0])
  let vmRuntimeDefine = $vmRuntimeProc.repr #We're just using the nim AST to generate the nimscript proc

  for i, param in paramTypes:
    var 
      getIdent: NimNode
      paramName = $param
    let
      xSym = param.bindSym 
      xType = xSym.getImpl()
      isAlias = (xType.kind == nnkTypeDef and xType[^1].kind == nnkSym and ($xType[^1]).isPrimitive)
    if isAlias: paramName = $xType[^1]
    if paramName in floatNames:
      getIdent = ident("getFloat")
    elif paramName in intNames:
      getIdent = ident("getInt")
    elif paramName == "bool":
      getIdent = ident("getBool")
    elif paramName == "string":
      getIdent = ident("getString")
    else:
      let 
        intLit = newIntLitNode(i)
        field = ident("field" & $i)
      objectConversion.add quote do:
        let `field` = `args`.getString(`intlit`).parseJson.to(`param`)
      procArgs.add field
      if not isAlias: vmCompDefine = vmCompDefine.replace($param, "string") #replaces the param with string as we cannot send objects across the nim -> nimscript barrier
    

    var paramType = ident(paramName)
    

    if getIdent != nil:
      procArgs.add newDotExpr(newCall(newDotExpr(args, getIdent),newIntLitNode(i)), paramType)
  
  result = newStmtList(input,
  quote do:
    static: scriptedTable.add(VmProcSignature(vmCompDefine: `vmCompDefine`, vmRunDefine: `vmRuntimeDefine`, name: `name`, vmProc: 
    proc(`args`: VmArgs){.closure, gcsafe.}= discard))
  )
  let objConst = result[1][0][0][1]
  if not hasRtnVal:
    objConst[4][1][6] = newStmtList(objectConversion).add(newCall(name, procArgs)) #Rewriting the body of the anon proc
  else:
    var procResultNode = newCall(name, procArgs)
    var isAlias = false
    if input[3][0].kind == nnkIdent:
      let
        xSym = input[3][0].bindSym 
        xType = xSym.getImpl()
      isAlias = (xType[^1].kind == nnkSym and ($xType[^1]).isPrimitive)
      if not isAlias and not ($input[3][0]).isPrimitive:
        procResultNode = newNimNode(nnkPrefix).add(ident("$"),newNimNode(nnkPrefix).add(ident("%"), procResultNode)) #if we have a return and it's an object convert from json
      objConst[4][1][6] = newStmtList(objectConversion).add(newCall(newDotExpr(args, ident("setResult")),procResultNode)) #Rewrite body of the anon proc