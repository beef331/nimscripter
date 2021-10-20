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

proc testObj*(c: ComplexObject) =
  assert $c == "(someInt: 320, someBool: false, someIntTwo: 42)"

proc test*(a: int, b: float) =
  assert 10 == a
  assert 20d == b

proc testRef*(j: SomeRef) = echo j[]

proc fromJson*: JsonNode = %* a

proc testJson*(j: JsonNode) =
  let c = j.to(ComplexObject)
  assert $c == """(someInt: 300, someBool: true, someString: "heel ya", secondaryBool: true, someOtherString: "Really cool?")"""

proc recObj*(r: RecObject) = 
  assert r.b == {"hello": "world"}.toTable
  assert r.next != nil

proc testTuple*(t: ((int, int), int, int, SomeRef)) =
  assert t[0] == (100, 200)
  assert t[1] == 200
  assert t[2] == 300
  assert t[3].a == 300