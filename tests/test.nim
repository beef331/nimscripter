
import unittest
import exportedprocs
#Needs to be exported after exposed procs
import ../src/nimscripter
import awbject
suite "nimscripter":
  test "mulby10":
    let intr = loadScript("tests/dothing.nims")
    check 100 == intr.get.invoke("doThingExported", [10.toPNode], int)
    check 300 == intr.get.invoke("doThingExported", [30.toPNode], int)
    check 10000 == intr.get.invoke("doThingExported", [1000.toPNode], int)
  test "getSeqObjects":
    let
      intr = loadScript("tests/getawbjects.nims", "awbject")
      expected = @[
        Awbject(a: 100, b: @[10f32, 30, 3.1415], name: "Steve"), 
        Awbject(a: 42, b: @[6.28f32], name: "Tau is better"),
        Awbject()]
      ret = intr.get.invoke("getAwbjectsExported", [], seq[Awbject])
    check expected == ret