import json
let a* = ComplexObject(
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

proc getCharSet*(s: set[char]): set[char] = s
proc getByteSet*(s: set[byte]): set[byte] = s
proc getIntSet*(s: set[355..357]): set[355..357] = s
proc getEnumSet*(s: set[SomeEnum]): set[SomeEnum] = s

proc getArray*(a: array[5, int]): array[5, int] = a
proc getSeq*(a: seq[int]): seq[int] = a
proc getString*(s: string): string = s

proc getRefSeq*(a: ref seq[int]): ref seq[int] = a

proc getProc*(a: proc(){.nimcall.}): proc(){.nimcall.} = a

template makeNumTest(T: typedesc[SomeOrdinal or char or SomeFloat]) = 
  proc `get T`*(a: T): T = a

makeNumTest(char)
makeNumTest(bool)
makeNumTest(SomeEnum)

makeNumTest(uint)
makeNumTest(int)

makeNumTest(uint8)
makeNumTest(int8)

makeNumTest(uint16)
makeNumTest(int16)

makeNumTest(uint32)
makeNumTest(int32)

makeNumTest(uint64)
makeNumTest(int64)

makeNumTest(float)
makeNumTest(float32)