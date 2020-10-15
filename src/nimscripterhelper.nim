import macros
import compiler / [ renderer, vmdef]
import sets
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

macro scripted*(input: untyped): untyped=
  var paramTypes: seq[string]
  for x in input[3]:
    if x.kind == nnkIdentDefs:
      for declared in 0..<(x.len-2):
        paramTypes.add $x[^2]

  let duplicated = copyNimTree(input)
  duplicated[duplicated.len - 1] = newNimNode(nnkDiscardStmt).add(newEmptyNode())

  let 
    vmDefine = $duplicated.repr
    name = $input[0]
    args = ident("args")

  result = newStmtList(input,
  quote do:
    static: scriptedTable.add(VmProcSignature(vmCompDefine: `vmDefine`, name: `name`, vmProc: 
    proc(`args`: VmArgs)= discard))
  )
  
  var procArgs: seq[NimNode]
  for i, param in paramTypes:
    var getIdent: NimNode 
    if param in floatNames:
      getIdent = ident("getFloat")
    elif param in intNames:
      getIdent = ident("getInt")
    elif param == "bool":
      getIdent = ident("getBool")
    elif param == "string":
      getIdent = ident("getString")

    var paramType = ident(param)

    procArgs.add newDotExpr(newCall(newDotExpr(args, getIdent),newIntLitNode(i)), paramType)
  let objConst = result[1][0][0][1]
  objConst[3][1][6] = newCall(name, procArgs) #Rewriting the body of the proc