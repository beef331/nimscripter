import objects
proc doStuff(a: ComplexObject) =
  discard
proc doStuffA(a: SomeRef) =
  discard
proc doStuffB(a: seq[int]) =
  discard
import json
let a = ComplexObject(
  someInt: 300,
  someBool: true,
  someString: "heel ya",
  secondaryBool: true,
  someOtherString: "Really cool?"
)
doStuff(a)
doStuffA(SomeRef(a: 100))
doStuffB(@[10, 20, 30, 10, 50, 100])

proc echoObj*(c: ComplexObject) = echo c
proc fromJson*(): JsonNode = %* a
