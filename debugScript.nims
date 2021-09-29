
proc saveInt(a: BiggestInt): string = discard

proc saveString(a: string): string = discard

proc saveBool(a: bool): string = discard

proc saveFloat(a: BiggestFloat): string = discard

proc getString(a: string, len: int, buf: string, pos: int): string = discard

proc getFloat(buf: string, pos: BiggestInt): BiggestFloat = discard

proc getInt(buf: string, pos: BiggestInt): BiggestInt = discard

import strutils

proc addToBuffer*[T](a: T, buf: var string) =
  when T is object or T is tuple or T is ref object:
    when T is ref object:
      addToBuffer(a.isNil, buf)
      if a.isNil: return
      for field in a[].fields:
        addToBuffer(field, buf)
    else:
      for field in a.fields:
        addToBuffer(field, buf)
  elif T is seq:
    addToBuffer(a.len, buf)
    for x in a:
      addToBuffer(x, buf)
  elif T is array:
    for x in a:
      addToBuffer(x, buf)
  elif T is SomeFloat:
    buf &= saveFloat(a.BiggestFloat)
  elif T is SomeOrdinal:
    buf &= saveInt(a.BiggestInt)
  elif T is string:
    buf &= saveString(a)


proc getFromBuffer*[T](buff: string, pos: var BiggestInt): T =
  if(pos > buff.len): echo "Buffer smaller than datatype requested"
  when T is object or T is tuple or T is ref object:
    when T is ref object:
      let isNil = getFromBuffer[bool](buff, pos)
      if isNil:
        return nil
      else: result = T()
      for field in result[].fields:
        field = getFromBuffer[field.typeof](buff, pos)
    else:
      for field in result.fields:
        field = getFromBuffer[field.typeof](buff, pos)
  elif T is seq:
    result.setLen(getFromBuffer[int](buff, pos))
    for x in result.mitems:
      x = getFromBuffer[typeof(x)](buff, pos)
  elif T is array:
    for x in result.mitems:
      x = getFromBuffer[typeof(x)](buff, pos)
  elif T is SomeFloat:
    result = getFloat(buff, pos).T
    pos += sizeof(BiggestInt)
  elif T is SomeOrdinal:
    result = getInt(buff, pos).T
    pos += sizeof(BiggestInt)
  elif T is string:
    let len = getFromBuffer[BiggestInt](buff, pos)
    result = buff[pos..<(pos + len)]
    pos += len

import macros
macro exportToNim(input: untyped): untyped =
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
    let idType = identDefs[^2]
    for param in identDefs[0..^3]:
      params.add param
      expBody.add quote do:
        let `param` = getFromBuffer[`idType`](`buffIdent`, `posIdent`)
  let procName = if input[0].kind == nnkPostfix: input[0][0] else: input[0]
  if hasRetVal:
    expBody.add quote do:
      `procName`().addToBuffer(result)
    if params.len > 0: expBody[^1][0][0].add params
  else:
    expBody.add quote do:
      `procName`()
    if params.len > 0: expBody[^1].add params
  exposed[^1] = expBody
  result = newStmtList(input, exposed)
proc multiplyBy10aintComp(parameters: string): string =
  discard
proc multiplyBy10(a: int): int =
  var data_101500658 = ""
  addToBuffer(a, data_101500658)
  var pos_101500659: BiggestInt
  result = getFromBuffer[int](multiplyBy10aintComp(data_101500658), pos_101500659)
proc doThing(a: int): int {.exportToNim.} = result = a.multiplyBy10
