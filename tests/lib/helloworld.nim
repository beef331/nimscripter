import ../../src/nimscripter/nimscr

import std/strformat

errorHook = proc(name: cstring, line, col: int, msg: cstring, sev: Severity) {.cdecl.} =
  echo fmt"{line}:{col}; {msg}"

proc doThing(args: VmArgs) {.cdecl.} = 
  echo args.getInt(0)

let prc = VmProcSignature(name: "doThing", runtimeImpl: "proc doThing(i: int) = discard", vmProc: doThing)
var addins = VmAddins(procs: cast[ptr UncheckedArray[typeof(prc)]](addr prc), procLen: 1)
const myScript = cstring"""
echo %*{"a": "Hello World"}

proc doThing*(): int =
  echo "Huh"
  30

proc doOtherThing*(a: int): string = $a

proc arrTest*(arr: openArray[int]): bool =
  echo arr
  arr == [0, 1, 2, 3, 4]

proc tupleTest*(a: int, b: string): (int, string) = (a, b)
proc inputTest*(a: (string, float, int, bool)) = echo a
doThing(200)
"""

let modules = [cstring"json"]

let intr = loadString(
  myScript,
  addins,
  modules,
  [],
  "/home/jason/.choosenim/toolchains/nim-#devel/lib",
  defaultDefines
  )

var 
  ret = intr.invoke("doThing", [])
  myVal: BiggestInt

assert ret.kind == nkIntLit
assert ret.getInt myVal
echo myVal


ret = intr.invoke("doOtherThing", [newNode(500)])
assert ret.kind == nkStrLit
var str: cstring
assert ret.getString(str)
echo str

let input = newNode(nkBracket)
for i in 0..<5:
  input.add newNode(i)
ret = intr.invoke("arrTest", [input])

assert ret.getInt(myVal) and bool(myVal)

ret = intr.invoke("tupleTest", [newNode(100), newNode("hello")])
assert (int, string).fromVm(ret) == (100, "hello")
ret = intr.invoke("tupleTest", [newNode(3100), newNode("world")])
assert (int, string).fromVm(ret) == (3100, "world")
discard intr.invoke("inputTest", [newNode ("hello", 32f, 100, true)])
