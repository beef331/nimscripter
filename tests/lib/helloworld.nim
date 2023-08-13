import ../../src/nimscripter/nimscr
import std/strformat

type Thing = object
  x, y: int
  s: set[char]

nimscr.init()
echo nimscr.version

errorHook = proc(name: cstring, line, col: int, msg: cstring, sev: Severity) {.cdecl.} =
  echo fmt"{line}:{col}; {msg}"

proc doThing(args: VmArgs) {.cdecl.} =
  assert args.getKind(0) == rkInt
  echo args.getInt(0)

let prc = 
  [
    VmProcSignature(package: "script", module: "script", name: "doSpecificThing", vmProc: doThing),
  ]


var addins = VmAddins(procs: cast[ptr UncheckedArray[typeof(prc[0])]](addr prc), procLen: prc.len)
const myScript = """
type Thing = object
  x, y: int
  s: set[char]

import std/json

proc doSpecificThing(i: int) = discard
proc getThing*(): Thing = Thing(x: 100, y: 200)

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
doSpecificThing(200)
"""
writeFile("/tmp/script.nim", myScript)

let intr = loadScript(
  "/tmp/script.nim",
  addins,
  [],
  "/home/jason/.choosenim/toolchains/nim-#devel/lib"
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
assert Thing.fromVm(intr.invoke("getThing", [])) == Thing(x: 100, y: 200)
