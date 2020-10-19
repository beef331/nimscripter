import macros
import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm]
import sets
import strutils
export VmArgs, nimeval, renderer, ast, types, llstream, vmdef, vm

type
  VmProcSignature* = object
    vmCompDefine*: string
    vmRunDefine*: string
    name*: string
    compName*: string
    vmProc*: proc(args: VmArgs){.closure, gcsafe.}

var scriptedTable*{.compileTime.}: seq[VmProcSignature]
const 
  scriptTable* = scriptedTable
