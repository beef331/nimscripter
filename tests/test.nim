
import unittest
import exportedprocs, awbject
#Needs to be exported after anything that implements nimscripted procs
import nimscripter
import nimscripter/expose
const mulProc = implNimscriptModule(multiply)
suite "nimscripter":
  test "Multiply By 10":
    let intr = loadScript("tests/dothing.nims", mulProc)
    var buff = ""
    check 100 == intr.get.invoke("doThing", buff, int)
    buff = ""
    check 300 == intr.get.invoke("doThing", buff, int)
    buff = ""
    check 10000 == intr.get.invoke("doThing", buff, int)

  test "Get Seq Objects":
    let
      intr = loadScript("tests/getawbjects.nims")
      expected = @[
        Awbject(a: 100, b: @[10f32, 30, 3.1415], name: "Steve"),
        Awbject(a: 42, b: @[6.28f32], name: "Tau is better"),
        Awbject()]
      ret = intr.get.invoke("getAwbjects", T = seq[Awbject])
    check expected == ret

  test "Non File Script":
    let script = """proc doThing(a: int): int {.exportToNim.} = result = a.multiplyBy10"""
    let intr = loadScript(script, mulProc, false)
    var buff = ""
    check 100 == intr.get.invoke("doThing", buff, int)
    buff = ""
    check 300 == intr.get.invoke("doThing", buff, int)
    buff = ""
    check 10000 == intr.get.invoke("doThing", buff, int)

  test "Import flat standard modules":
    let script = "import strutils" # stdlib/pure/strutils.nim
    let intr = loadScript(script, false)
    check intr.isSome

  test "Import deep standard modules":
    let script = "import sequtils" # stdlib/pure/collections/sequtils.nim
    let intr = loadScript(script, false)
    check intr.isSome

  test "Returning ref":
    let script = """
type SomeRef = ref object
  a: int

proc getSomeRef: SomeRef {.exportToNim.} = SomeRef(a: 100)
"""
    type SomeRef = ref object
      a: int
    let intr = loadScript(script, false)
    assert intr.get.invoke("getSomeRef", T = SomeRef).a == 100
