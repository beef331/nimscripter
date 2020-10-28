import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm, lineinfos, passes]
import os, osproc, strutils, algorithm
import json
import options
import vmtable
import nimscripted
export destroyInterpreter, options, Interpreter

import marshalns

# This uses your Nim install to find the standard library instead of hard-coding it
var
  nimdump = execProcess("nim dump")
  nimlibs = nimdump[nimdump.find("-- end of list --")+18..^2].split
nimlibs.sort

const scriptAdditions = static:
  var additions = block:"""
type Test = object
  x, y: float
proc saveInt(a: int, buffer: string): string = discard

proc saveString(a: string, buffer: string): string = discard

proc saveBool(a: bool, buffer: string): string = discard

proc saveFloat(a: float, buffer: string): string = discard

proc getString(a: string, len: int, buf: string, pos: int): string = discard

proc getFloat(buf: string, pos: BiggestInt): BiggestFloat = discard

proc getInt(buf: string, pos: BiggestInt): BiggestInt = discard

type Collection[T] = concept c
  c[0] is T

proc addToBuffer[T](a: T, buf: var string) =
  when T is object or T is tuple:
    for field in a.fields:
      addToBuffer(field, buf)
  elif T is Collection:
    addToBuffer(a.len, buf)
    for x in a:
      addToBuffer(a, buf)
  elif T is SomeFloat:
    buf &= saveFloat(a, buf)
  elif T is SomeOrdinal:
    buf &= saveInt(a.int, buf)
  elif T is string:
    buf &= saveString(a, buf)

proc getFromBuffer(buff: string, T: typedesc, pos: var BiggestInt): T=
  when T is object or T is tuple:
    for field in result.fields:
      field = getFromBuffer(buff, field.typeof, pos)
  elif T is seq:
    result.setLen(getFromBuffer(buff, int, pos))
    for x in result.mitems:
      x = getFromBuffer(buff: string, x.typeof, pos)
  elif T is SomeFloat:
    result = getFloat(buff, pos).T
    pos += sizeof(BiggestInt)
  elif T is SomeOrdinal:
    result = getInt(buff, pos).T
    pos += sizeof(BiggestInt)
  elif T is string:
    let len = getInt(buff, pos)
    result = buff[pos..<(pos+len)]
    pos += len
"""
  for vmProc in scriptTable:
    additions &= vmProc.vmCompDefine
    additions &= vmProc.vmRunDefine
  additions

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
    intr.implementRoutine("*", scriptname, "saveInt", proc(vm: VmArgs)=
      let a = vm.getInt(0)
      let buf = vm.getString(1)
      vm.setResult(saveInt(a, buf))
    )
    intr.implementRoutine("*", scriptname, "saveFloat", proc(vm: VmArgs)=
      let a = vm.getFloat(0)
      let buf = vm.getString(1)
      vm.setResult(saveFloat(a, buf))
    )
    intr.implementRoutine("*", scriptname, "saveString", proc(vm: VmArgs)=
      let a = vm.getstring(0)
      let buf = vm.getString(1)
      vm.setResult(saveString(a, buf))
    )
    intr.implementRoutine("*", scriptname, "getInt", proc(vm: VmArgs)=
      let 
        buf = vm.getString(0)
        pos = vm.getInt(1)
      vm.setResult(getInt(buf, pos))
    )
    intr.implementRoutine("*", scriptname, "getFloat", proc(vm: VmArgs)=
      let 
        buf = vm.getString(0)
        pos = vm.getInt(1)
      vm.setResult(getFloat(buf, pos))
    )
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

discard loadScript("./test.nims", [])