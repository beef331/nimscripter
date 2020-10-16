import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm]
import os, osproc, strutils, algorithm
import nimscripterhelper
import json
export destroyInterpreter

# This uses your Nim install to find the standard library instead of hard-coding it
var
  nimdump = execProcess("nim dump")
  nimlibs = nimdump[nimdump.find("-- end of list --")+18..^2].split
nimlibs.sort

proc toPNode*[T](a: T): PNode = 
  when T is SomeOrdinal:
    newIntNode(nkIntLit, a)
  elif T is SomeFloat:
    newFloatNode(nkFloatLit, a)
  elif T is string:
    newStrNode(nkStrLit, a)
  else: newStrNode(nkStrLit, $ (%a))

const scriptAdditions = block:
  #Due to our reliance on json for object transfer need json
  var scriptAddition = """
import json
import macros, sets
const 
  intNames = ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "byte", "uint16", "uint32", "uint64"].toHashSet
  floatNames = ["float32", "float", "float64"].toHashSet

proc isPrimitive(str: string): bool = str in intNames + floatNames + ["bool", "string"].toHashSet

macro interoped(procDef: untyped): untyped =
  var 
    newProcArgs: seq[NimNode]
    oldProcTypes: seq[NimNode]
    hasReturn = false
    hasNonPrimitiveArgs = false
  if procDef[3][0].kind != nnkEmpty and not ($procDef[3][0]).isPrimitive:
    hasReturn = true
    newProcArgs.add ident("string")
  else:
    newProcArgs.add procDef[3][0]

  for param in procDef[3]:
    if param.kind == nnkIdentDefs:
      #For each declared variable here
      for declared in 0..<(param.len-2):
        #If it's not a primitive convert to json, else just send it
        newProcArgs.add(param)
        oldProcTypes.add(param[^2])
        if not ($param[^2]).isPrimitive:
          newProcArgs[^1][^2] = ident("string")
          hasNonPrimitiveArgs = true
  if newProcArgs.len == 0:
    if procDef[0].kind == nnkident:
      procDef[0] = postfix(procDef[0],"*") 
    return procDef
  var 
    newBody = newStmtList()
    args: seq[NimNode]
  args.add(procDef[0])
  for i, arg in newProcArgs:
      for declared in 0..<(arg.len-2):
        args.add(arg[declared])
        newBody.add newLetStmt(arg[declared], newCall(newNimNode(nnkBracketExpr).add(ident("fromString"),oldProcTypes[declared]), arg[declared]))
  newBody.add newNimNode(nnkCall).add(args)
  if hasReturn: 
    newBody[0] = newDotExpr(newBody[0], ident("toString"))
    let exposedProc = newProc(postfix(procDef[0], "*"), newProcArgs, newBody)
    result = newStmtList(procDef, exposedProc)
  elif not hasNonPrimitiveArgs: 
    newBody = procDef[6]
    let exposedProc = newProc(postfix(procDef[0], "*"), newProcArgs, newBody)
    result = newStmtList(exposedProc)
  echo result.repr

proc fromString[T: object](a: string): T = parseJson(a).to(T)
proc toString(a: object): string = $(% a)
"""
  for scriptProc in scriptedTable:
    scriptAddition &= scriptProc.vmCompDefine
    scriptAddition &= scriptProc.vmRunDefine
  scriptAddition

proc loadScript*(path: string, modules: varargs[string]): Interpreter=
  var additions = scriptAdditions
  
  for `mod` in modules:
    additions.insert("import " & `mod` & "\n", 0)

  let
    scriptName = path.splitFile.name
    intr = createInterpreter(path, nimlibs)
    script = readFile(path)

  for scriptProc in scriptTable:
    intr.implementRoutine("*", scriptname, scriptProc.name & "Comp", scriptProc.vmProc)
  writeFile("main2.nims",additions & script)
  intr.evalScript(llStreamOpen(additions & script))
  intr

proc invoke*(intr: Interpreter, procName: string, args: openArray[PNode] = [], T: typeDesc): T=
  let 
    foreignProc = intr.selectRoutine(procName)
    ret = intr.callRoutine(foreignProc, args)
  when T is SomeOrdinal:
    ret.intVal.T
  elif T is SomeFloat:
    ret.floatVal.T
  elif T is string:
    ret.strVal
  elif not T is void:
    to((ret.strVal).parseJson, T)