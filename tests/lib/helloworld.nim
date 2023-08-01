import ../../src/nimscripter/nimscr

import std/strformat

errorHook = proc(name: cstring, line, col: int, msg: cstring, sev: Severity) {.cdecl.} =
  echo fmt"{line}:{col}; {msg}"

var addins = VmAddins()
const myScript = cstring"""
echo %*{"a": "Hello World"}

proc doThing*(): int =
  echo "Huh"
  30

proc doOtherThing*(a: int): string = $a

proc arrTest*(arr: openArray[int]): bool =
  echo arr
  arr == [0, 1, 2, 3, 4]
"""

let modules = cstring"json"

let intr = loadString(
  myScript,
  addins,
  cast[ptr UncheckedArray[cstring]](modules.addr).toOpenArray(0, 0),
  [],
  "/home/jason/.choosenim/toolchains/nim-#devel/lib",
  defaultDefines
  )

var 
  ret = intr.invoke("doThing", [])
  myVal: BiggestInt

assert ret.pnodeGetKind == nkIntLit
assert ret.pnodeGetInt myVal
echo myVal


ret = intr.invoke("doOtherThing", [intNode(500)])
assert ret.pnodeGetKind == nkStrLit
var str: cstring
assert ret.pnodeGetString(str)
echo str

let input = newNode(nkBracket)
for i in 0..<5:
  input.pNodeAdd(intNode(i))
ret = intr.invoke("arrTest", [input])

assert ret.pnodeGetInt(myVal) and bool(myVal)
