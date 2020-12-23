import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm]
export VmArgs, nimeval, renderer, ast, types, llstream, vmdef, vm

type
  VmProcSignature* = object
    vmCompDefine*: string
    vmRunDefine*: string
    name*: string
    compName*: string
    vmProc*: proc(args: VmArgs){.closure, gcsafe.}

var 
  scriptedTable*{.compileTime.}: seq[VmProcSignature]
  exportedCode*{.compileTime.}: seq[string]
const 
  scriptTable* = scriptedTable
  vmTypeDefs* = exportedCode
