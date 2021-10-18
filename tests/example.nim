import nimscripter
import nimscripter/expose
import example/objects
import compiler/nimeval
import json

var compl: ComplexObject
proc doStuff(a: ComplexObject) = compl = a
proc doStuffA(a: SomeRef) = assert a.a == 100
proc doStuffB(a: seq[int]) = assert a == @[10, 20, 30, 10, 50, 100]

exportTo(test,
  doStuff,
  doStuffA,
  doStuffB,
  ComplexObject,
  SomeRef,
  RecObject
  )
const
  (testProc, additions) = implNimscriptModule(test)
  stdlib = findNimStdlibCompileTime()
let
  intr = loadScript(NimScriptPath("tests/example/first.nims"), testProc, additions = additions, modules = ["tables"], stdpath = stdlib)
  res = intr.get.invoke(fromJson, returnType = JsonNode)
assert $res == """{"someInt":300,"someBool":true,"someString":"heel ya","secondaryBool":true,"someOtherString":"Really cool?"}"""
intr.get.invoke(testObj, ComplexObject(someBool: false, someInt: 320, someintTwo: 42))
intr.get.invoke(test, 10, 20d, returnType = void)
intr.get.invoke(testTuple, ((100, 200), 200, 300, SomeRef(a: 300)))
intr.get.invoke(recObj, RecObject(next: RecObject(), b: {"hello": "world"}.toTable))
intr.get.invoke(testJson, %* compl)
