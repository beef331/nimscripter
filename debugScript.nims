type Test = object
  x, y: float
proc saveInt(a: int, buffer: string): string = discard

proc saveString(a: string, buffer: string): string = discard

proc saveBool(a: bool, buffer: string): string = discard

proc saveFloat(a: float, buffer: string): string = discard

proc getString(a: string, len: int, buf: string, pos: int): string = discard

proc getFloat(buf: string, pos: BiggestInt): BiggestFloat = discard

proc getInt(buf: string, pos: BiggestInt): BiggestInt = discard

type Collection[T] = concept c
  c[0] is T

proc addToBuffer[T](a: T, buf: var string) =
  when T is object or T is tuple:
    for field in a.fields:
      addToBuffer(field, buf)
  elif T is Collection:
    addToBuffer(a.len, buf)
    for x in a:
      addToBuffer(a, buf)
  elif T is SomeFloat:
    buf &= saveFloat(a, buf)
  elif T is SomeOrdinal:
    buf &= saveInt(a.int, buf)
  elif T is string:
    buf &= saveString(a, buf)

proc getFromBuffer(buff: string, T: typedesc, pos: var BiggestInt): T=
  when T is object or T is tuple:
    for field in result.fields:
      field = getFromBuffer(buff, field.typeof, pos)
  elif T is seq:
    result.setLen(getFromBuffer(buff, int, pos))
    for x in result.mitems:
      x = getFromBuffer(buff: string, x.typeof, pos)
  elif T is SomeFloat:
    result = getFloat(buff, pos).T
    pos += sizeof(BiggestInt)
  elif T is SomeOrdinal:
    result = getInt(buff, pos).T
    pos += sizeof(BiggestInt)
  elif T is string:
    let len = getInt(buff, pos)
    result = buff[pos..<(pos+len)]
    pos += len
proc testabct(parameters: string) =
  discard
proc test(a: int; b: float; c: string; t: Test) =
  var params = ""
  addToBuffer(a, params)
  addToBuffer(b, params)
  addToBuffer(c, params)
  addToBuffer(t, params)
  testabct(params)
type A = object
  x,y: float32
type B = object
  a: int
  b: A

let b = B(a: 100, b: A(x: 3.3210f, y: 1.321321f))

var 
  buf = ""
  pos: BiggestInt = 0
b.addToBuffer(buf)
echo getFromBuffer(buf, B, pos)
test(10, 42.424242f, "Hmmm it works", Test(x: 100, y: 321))
