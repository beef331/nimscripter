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
proc test*(a: int, b: float) = echo a, " ", b
proc echoRef*(j: SomeRef) = echo j[]
proc echoJson*(j: JsonNode) = 
  let a = j.to(int)
  echo a

proc fromJson*(): JsonNode = %* a
