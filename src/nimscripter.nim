import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm, lineinfos, passes]
import os, osproc, strutils, algorithm
import json
import options
import vmtable
import nimscripted
export destroyInterpreter, options, Interpreter

import marshalns
export marshalns

# This uses your Nim install to find the standard library instead of hard-coding it
var
  nimdump = execProcess("nim dump")
  nimlibs = nimdump[nimdump.find("-- end of list --")+18..^2].split
nimlibs.sort

proc toPNode*(s: string): PNode = newStrNode(nkStrLit, s)

const scriptAdditions = static:
  var additions = block:"""

proc saveInt(a: BiggestInt): string = discard

proc saveString(a: string): string = discard

proc saveBool(a: bool): string = discard

proc saveFloat(a: BiggestFloat): string = discard

proc getString(a: string, len: int, buf: string, pos: int): string = discard

proc getFloat(buf: string, pos: BiggestInt): BiggestFloat = discard

proc getInt(buf: string, pos: BiggestInt): BiggestInt = discard

import strutils

proc addToBuffer*[T](a: T, buf: var string) =
  when T is object or T is tuple or T is ref object:
    when T is ref object:
      addToBuffer(a.isNil, buf)
      if a.isNil: return
      for field in a[].fields:
        addToBuffer(field, buf)
    else:
      for field in a.fields:
        addToBuffer(field, buf)
  elif T is seq:
    addToBuffer(a.len, buf)
    for x in a:
      addToBuffer(x, buf)
  elif T is array:
    for x in a:
      addToBuffer(x, buf)
  elif T is SomeFloat:
    buf &= saveFloat(a.BiggestFloat)
  elif T is SomeOrdinal:
    buf &= saveInt(a.BiggestInt)
  elif T is string:
    buf &= saveString(a)


proc getFromBuffer*(buff: string, T: typedesc, pos: var BiggestInt): T=
  if(pos > buff.len): echo "Buffer smaller than datatype requested"
  when T is object or T is tuple or T is ref object:
    when T is ref object:
      let isNil = getFromBuffer(buff, bool, pos)
      if isNil: 
        return nil
      else: result = T()
      for field in result[].fields:
        field = getFromBuffer(buff, field.typeof, pos)
    else:
      for field in result.fields:
        field = getFromBuffer(buff, field.typeof, pos)
  elif T is seq:
    result.setLen(getFromBuffer(buff, int, pos))
    for x in result.mitems:
      x = getFromBuffer(buff, typeof(x), pos)
  elif T is array:
    for x in result.mitems:
      x = getFromBuffer(buff, typeof(x), pos)
  elif T is SomeFloat:
    result = getFloat(buff, pos).T
    pos += sizeof(BiggestInt)
  elif T is SomeOrdinal:
    result = getInt(buff, pos).T
    pos += sizeof(BiggestInt)
  elif T is string:
    let len = getFromBuffer(buff, BiggestInt, pos)
    result = buff[pos..<(pos + len)]
    pos += len

import macros
macro exportToNim(input: untyped): untyped=
  let 
    exposed = copy(input)
    hasRetVal = input[3][0].kind != nnkEmpty
  if exposed[0].kind == nnkPostfix:
    exposed[0][0] = ident($exposed[0][0] & "Exported")
  else:
    exposed[0] = postfix(ident($exposed[0] & "Exported"), "*")
  if hasRetVal:
    exposed[3][0] = ident("string")

  if exposed[3].len > 2:
    exposed[3].del(2, exposed[3].len - 2)
  if exposed[3].len > 1:
    exposed[3][1] = newIdentDefs(ident("parameters"), ident("string"))
  
  let
    buffIdent = ident("parameters")
    posIdent = ident("pos")
  var
    params: seq[NimNode]
    expBody = newStmtList().add quote do:
      var `posIdent`: BiggestInt = 0
  for identDefs in input[3][1..^1]:
    let idType = ident($identDefs[^2])
    for param in identDefs[0..^3]:
      params.add param
      expBody.add quote do:
        let `param` = getFromBuffer(`buffIdent`, `idType`, `posIdent`)
  let procName = if input[0].kind == nnkPostfix: input[0][0] else: input[0]
  if hasRetVal:
    expBody.add quote do:
      `procName`().addToBuffer(result)
    if params.len > 0: expBody[^1][0][0].add params
  else:
    expBody.add quote do:
      `procName`()
    if params.len > 0: expBody[^1].add params
  exposed[^1] = expBody
  result = newStmtList(input, exposed)
"""
  for types in vmtypeDefs:
    additions &= types
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
      vm.setResult(saveInt(a))
    )
    intr.implementRoutine("*", scriptname, "saveFloat", proc(vm: VmArgs)=
      let a = vm.getFloat(0)
      vm.setResult(saveFloat(a))
    )
    intr.implementRoutine("*", scriptname, "saveString", proc(vm: VmArgs)=
      let a = vm.getstring(0)
      vm.setResult(saveString(a))
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
  else:
    when defined(debugScript):
      echo "File not found"

proc invoke*(intr: Interpreter, procName: string, args: openArray[PNode] = [], T: typeDesc = void): T=
  let 
    foreignProc = intr.selectRoutine(procName)
    ret = intr.callRoutine(foreignProc, args)
  when T isnot void:
    var pos: BiggestInt
    getFromBuffer(ret.strVal, T, pos)
