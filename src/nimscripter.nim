import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm]
import osproc, strutils, algorithm
import nimscripterhelper
import awbject
import json
# This uses your Nim install to find the standard library instead of hard-coding it
var
  nimdump = execProcess("nim dump")
  nimlibs = nimdump[nimdump.find("-- end of list --")+18..^2].split
nimlibs.sort
proc fire(damage: int, x, y: float32){.scripted.}=
  echo damage, " ", x, " ", y

proc cry(doCry: bool, message: string){.scripted.}=
  if doCry: echo message
  else: echo "You are not sad"

proc kill(a: Awbject){.scripted.}=
  echo a.a

let
  intr = createInterpreter("script.nims", nimlibs)
  script = readFile("script.nims")

var scriptAddition = "import src/awbject\nimport json\n"
for scriptProc in scriptTable:
  scriptAddition &= scriptProc.vmCompDefine
  scriptAddition &= scriptProc.vmRunDefine
  echo scriptProc
  intr.implementRoutine("*", "script", scriptProc.name & "Comp", scriptProc.vmProc)
intr.evalScript(llStreamOpen(scriptAddition & script))
intr.destroyInterpreter()