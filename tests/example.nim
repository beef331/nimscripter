import nimscripter
import nimscripter/expose
import example/objects
import compiler/nimeval
import json

var compl: ComplexObject
proc doStuff(a: ComplexObject) = compl = a
proc doStuffA(a: SomeRef) =
  if a != nil:
    echo a.a
proc doStuffB(a: seq[int]) = echo a

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
  intr = loadScript("tests/example/first.nims".NimScriptPath, testProc, additions = additions, modules = ["tables"], stdpath = stdlib)
  res = intr.get.invoke(fromJson, returnType = JsonNode)
echo res.pretty

intr.get.invoke(echoObj, ComplexObject(someBool: false, someInt: 320, someintTwo: 42))
intr.get.invoke(test, 10, 20d, returnType = void)
intr.get.invoke(echoTuple, ((100, 200), 200, 300, SomeRef(a: 300)))
intr.get.invoke(recObj, RecObject(next: RecObject(), b: {"hello": "world"}.toTable))
intr.get.invoke(echoJson, %* compl)
