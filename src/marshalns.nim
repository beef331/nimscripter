import streams

proc saveInt*(a: BiggestInt): string =
  let ss = newStringStream("")
  ss.write(a)
  ss.setPosition(0)
  result = ss.readAll()
  ss.close()

proc saveString*(a: string): string =
  let ss = newStringStream("")
  ss.write(a.len)
  ss.write(a)
  ss.setPosition(0)
  result = ss.readAll()
  ss.close()

proc saveBool*(a: bool): string =
  let ss = newStringStream("")
  ss.write(a)
  ss.setPosition(0)
  result = ss.readAll()
  ss.close()

proc saveFloat*(a: BiggestFloat): string =
  let ss = newStringStream("")
  ss.write(a)
  ss.setPosition(0)
  result = ss.readAll()
  ss.close()

proc getInt*(buff: string, pos: BiggestInt): BiggestInt =
  let ss = newStringStream(buff)
  ss.setPosition(pos.int)
  ss.read(result)
  ss.close()

proc getFloat*(buff: string, pos: BiggestInt): BiggestFloat =
  let ss = newStringStream(buff)
  ss.setPosition(pos.int)
  ss.read(result)
  ss.close()

type Collection[T] = concept c
  c[0] is T

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
      x = getFromBuffer(buff, typeof(x), pos)
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