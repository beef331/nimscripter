import compiler / [nimeval, renderer, ast, types, llstream, vmdef, vm]
import osproc, strutils, algorithm
import nimscripterhelper
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

const scriptTable = static(scriptedTable)

let
  intr = createInterpreter("script.nims", nimlibs)
  script = readFile("script.nims")

# We forward declare scriptProc here to ensure it has the right signature
# Specifying a llStream to read from will not run top-level things from the
# script like it usually would. The name given above will only be used for errors.
intr.implementRoutine("*", "script", "compilerProc", proc (a: VmArgs) =
  a.setResult(a.getInt(0) + a.getInt(1))
)
var scriptAddition = ""
for scriptProc in scriptTable:
  scriptAddition &= scriptProc.vmCompDefine
  intr.implementRoutine("*", "script", scriptProc.name, scriptProc.vmProc)
intr.evalScript(llStreamOpen(scriptAddition & script))
intr.destroyInterpreter()