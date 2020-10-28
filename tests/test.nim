
import unittest
import exportedprocs
#Needs to be exported after exposed procs
import ../src/nimscripter
import awbject
suite "nimscripter":
  test "mulby10":
    let intr = loadScript("tests/dothing.nims")
    var buff = ""
    10.addToBuffer(buff)
    check 100 == intr.get.invoke("doThingExported", [buff.toPNode()], int)
    buff = ""
    30.addToBuffer(buff)
    check 300 == intr.get.invoke("doThingExported", [buff.toPNode()], int)
    buff = ""
    1000.addToBuffer(buff)
    check 10000 == intr.get.invoke("doThingExported", [buff.toPNode()], int)
  #[
  test "getSeqObjects":
    let
      intr = loadScript("tests/getawbjects.nims", "awbject")
      expected = @[
        Awbject(a: 100, b: @[10f32, 30, 3.1415], name: "Steve"), 
        Awbject(a: 42, b: @[6.28f32], name: "Tau is better"),
        Awbject()]
      ret = intr.get.invoke("getAwbjectsExported", [], seq[Awbject])
    check expected == ret
  ]#