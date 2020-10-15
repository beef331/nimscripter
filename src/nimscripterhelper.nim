import macros
import compiler / [ renderer, vmdef]
import sets
import awbject
import strutils
export VmArgs
type
  VmProcSignature* = object
    vmCompDefine*: string
    name*: string
    vmProc*: proc(args: VmArgs){.closure, gcsafe.}

var scriptedTable*{.compileTime.}: seq[VmProcSignature]
const 
  scriptTable* = scriptedTable
  intNames = ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "byte", "uint16", "uint32", "uint64"].toHashSet
  floatNames = ["float32", "float", "float64"].toHashSet
{.experimental: "dynamicBindSym".} 
macro scripted*(input: untyped): untyped=
  var paramTypes: seq[NimNode]
  for x in input[3]:
    if x.kind == nnkIdentDefs:
      for declared in 0..<(x.len-2):
        paramTypes.add x[^2]

  let duplicated = copyNimTree(input)
  duplicated[duplicated.len - 1] = newNimNode(nnkDiscardStmt).add(newEmptyNode())

  var 
    vmDefine = $duplicated.repr
    name = $input[0]
    args = ident("args")

  var 
    procArgs: seq[NimNode]
    objectConversion: seq[NimNode]
  for i, param in paramTypes:
    var 
      getIdent: NimNode
      paramName = $param
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
      vmDefine = vmDefine.replace($param, "string")

    var paramType = ident(paramName)
    

    if getIdent != nil:
      procArgs.add newDotExpr(newCall(newDotExpr(args, getIdent),newIntLitNode(i)), paramType)
  
  result = newStmtList(input,
  quote do:
    static: scriptedTable.add(VmProcSignature(vmCompDefine: `vmDefine`, name: `name`, vmProc: 
    proc(`args`: VmArgs)= discard))
  )

  let objConst = result[1][0][0][1]
  objConst[3][1][6] = newStmtList(objectConversion).add(newCall(name, procArgs)) #Rewriting the body of the proc
  echo result.repr