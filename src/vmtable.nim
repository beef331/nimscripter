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
    vmProc*: proc(args: VmArgs){.closure, gcsafe.}

var scriptedTable*{.compileTime.}: seq[VmProcSignature]
const 
  scriptTable* = scriptedTable
  intNames = ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "byte", "uint16", "uint32", "uint64"].toHashSet
  floatNames = ["float32", "float", "float64"].toHashSet
