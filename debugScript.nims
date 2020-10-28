type Test = object
  x, y: float
  z: string
proc saveInt(a: BiggestInt): string = discard

proc saveString(a: string): string = discard

proc saveBool(a: bool): string = discard

proc saveFloat(a: BiggestFloat): string = discard

proc getString(a: string, len: int, buf: string, pos: int): string = discard

proc getFloat(buf: string, pos: BiggestInt): BiggestFloat = discard

proc getInt(buf: string, pos: BiggestInt): BiggestInt = discard

type Collection[T] = concept c
  c[0] is T
  c.len is int

proc addToBuffer*[T](a: T, buf: var string) =
  when T is object or T is tuple:
    for field in a.fields:
      addToBuffer(field, buf)
  elif T is Collection and T isnot string:
    addToBuffer(a.len, buf)
    for x in a:
      addToBuffer(x, buf)
  elif T is SomeFloat:
    buf &= saveFloat(a.BiggestFloat)
  elif T is SomeOrdinal:
    buf &= saveInt(a.BiggestInt)
  elif T is string:
    buf &= saveString(a)

proc getFromBuffer*(buff: string, T: typedesc, pos: var BiggestInt): T=
  if(pos > buff.len): echo "Buffer smaller than datatype requested"
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
    let len = getFromBuffer(buff, BiggestInt, pos)
    result = buff[pos..<(pos + len)]
    pos += len
import macros, strutils
macro exportToNim(input: untyped): untyped=
  let 
    exposed = copy(input)
    hasRetVal = input[3][0].kind != nnkEmpty
  if exposed[0].kind == nnkPostfix:
    exposed[0][0] = ident($exposed[0][0] & "Exported")
  else:
    exposed[0] = postfix(ident($exposed[0] & "Exported"), "*")
  if hasRetVal:
    exposed[3][0] = ident("string")

  if exposed[3].len > 2:
    exposed[3].del(2, exposed[3].len - 2)
  if exposed[3].len > 1:
    exposed[3][1] = newIdentDefs(ident("parameters"), ident("string"))
  
  let
    buffIdent = ident("parameters")
    posIdent = ident("pos")
  var
    params: seq[NimNode]
    expBody = newStmtList().add quote do:
      var `posIdent`: BiggestInt = 0
  for identDefs in input[3][1..^1]:
    let idType = ident($identDefs[^2])
    for param in identDefs[0..^3]:
      params.add param
      expBody.add quote do:
        let `param` = getFromBuffer(`buffIdent`, `idType`, `posIdent`)
  let procName = if input[0].kind == nnkPostfix: input[0][0] else: input[0]
  expBody.add quote do:
    `procName`().addToBuffer(result)
  expBody[^1][0][0].add params
  exposed[^1] = expBody
  result = newStmtList(input, exposed)
  echo result.repr
proc testabct(parameters: string) =
  discard
proc test(a: int; b: float; c: string; t: Test) =
  var params = ""
  addToBuffer(a, params)
  addToBuffer(b, params)
  addToBuffer(c, params)
  addToBuffer(t, params)
  testabct(params)
proc multiplyBy10a(parameters: string): string =
  discard
proc multiplyBy10(a: int): int =
  var params = ""
  addToBuffer(a, params)
  var
    returnBuf = ""
    pos: BiggestInt = 0
  multiplyBy10a(params).addToBuffer(returnBuf)
  getFromBuffer(returnBuf, int, pos)
proc doThing(a: int): int {.exportToNim.} =
  result = a.multiplyBy10
