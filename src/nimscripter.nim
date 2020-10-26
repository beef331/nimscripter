import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm, lineinfos, passes]
import os, osproc, strutils, algorithm
import json
import options
import vmtable
export destroyInterpreter, options, Interpreter



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

macro exportToNim(procDef: untyped): untyped =
  var 
    newProcArgs: seq[NimNode]
    oldProcTypes: seq[NimNode]
    hasReturn = false
    returnIsPrimitive = true
    hasNonPrimitiveArgs = false
  if procDef[3][0].kind != nnkEmpty:
    hasReturn = true
    if (procDef[3][0].kind == nnkIdent and not ($procDef[3][0]).isPrimitive) or procDef[3][0].kind != nnkident:
      returnIsPrimitive = false
  newProcArgs.add procDef[3][0]
  
  var argConversion = newStmtList()

  for param in procDef[3]:
    if param.kind == nnkIdentDefs:
      #For each declared variable here
      for declared in 0..<(param.len-2):
        #If it's not a primitive convert to json, else just send it
        newProcArgs.add(param)
        let 
          paramName = param[declared]
          paramType = param[^2]
        if param[^2].kind != nnkident or not ($param[^2]).isPrimitive:
          newProcArgs[^1][^2] = ident("string")
          hasNonPrimitiveArgs = true
          argConversion.add quote do:
            let `paramName` = `paramName`.parseJson.to(`paramType`)
  if newProcArgs.len == 0:
    if procDef[0].kind == nnkident:
      procDef[0] = postfix(procDef[0],"*") 
    return procDef
  var 
    newBody = newStmtList()
    args: seq[NimNode]
  for i, arg in newProcArgs:
      for declared in 0..<(arg.len-2):
        args.add(arg[declared])
        if not ($arg[^2]).isPrimitive:
          newBody.add newLetStmt(arg[declared], newCall(newNimNode(nnkBracketExpr).add(ident("fromString"),newProcArgs[declared]), arg[declared]))
  newBody.add newCall(procDef[0], args)
  let exposedName = ident ($procDef[0]) & "Exported"
  if hasReturn or hasNonPrimitiveArgs:
    newBody.insert 0, argConversion
    if not returnIsPrimitive: newBody[0] = newDotExpr(newBody[0], ident("toString"))
    let exposedProc = newProc(postfix(exposedName, "*"), newProcArgs, newBody)
    if not returnIsPrimitive:
      exposedProc[3][0] = ident("string")
    result = newStmtList(procDef, exposedProc)
  else: 
    newBody = procDef[6]
    let exposedProc = newProc(postfix(exposedName, "*"), newProcArgs, newBody)
    result = newStmtList(exposedProc)
proc fromString[T](a: string): T = parseJson(a).to(T)
proc toString[T](a: T): string = $(% a)
"""
  for scriptProc in scriptedTable:
    scriptAddition &= scriptProc.vmCompDefine
    scriptAddition &= scriptProc.vmRunDefine
  scriptAddition

type
  VMQuit* = object of CatchableError
    info*: TLineInfo

proc loadScript*(path: string, modules: varargs[string]): Option[Interpreter]=
  if fileExists path:
    var additions = scriptAdditions
  
    for `mod` in modules:
      additions.insert("import " & `mod` & "\n", 0)
    
    let
      scriptName = path.splitFile.name
      intr = createInterpreter(path, nimlibs)
      script = readFile(path)
    for scriptProc in scriptTable:
      intr.implementRoutine("*", scriptname, scriptProc.compName, scriptProc.vmProc)
    when defined(debugScript): writeFile("debugScript.nims",additions & script)
    
    #Throws Error so we can catch it
    intr.registerErrorHook proc(config, info, msg, severity: auto) {.gcsafe.} =
      if severity == Error and config.error_counter >= config.error_max:
        echo "Script Error: ", info, " ", msg
        raise (ref VMQuit)(info: info, msg: msg)
    try:
      intr.evalScript(llStreamOpen(additions & script))
      result = option(intr)
    except:
      discard

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
  elif T isNot void:
    to((ret.strVal).parseJson, T)