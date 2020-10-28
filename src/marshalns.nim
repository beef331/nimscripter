import streams

proc saveInt*(a: BiggestInt, buffer: string): string =
  let ss = newStringStream(buffer)
  ss.write(a)
  ss.setPosition(0)
  ss.readAll()

proc saveString*(a: string, buffer: string): string = buffer & a

proc saveBool*(a: bool, buffer: string): string =
  let ss = newStringStream(buffer)
  ss.write(a)
  ss.setPosition(0)
  ss.readAll()

proc saveFloat*(a: BiggestFloat , buffer: string): string =
  let ss = newStringStream(buffer)
  ss.write(a)
  ss.setPosition(0)
  ss.readAll()

proc getInt*(buff: string, pos: BiggestInt): BiggestInt =
  let ss = newStringStream(buff)
  ss.setPosition(pos.int)
  ss.read(result)

proc getFloat*(buff: string, pos: BiggestInt): BiggestFloat =
  let ss = newStringStream(buff)
  ss.setPosition(pos.int)
  ss.read(result)

type Collection[T] = concept c
  c[0] is T

proc addToBuffer*[T](a: T, buf: var string) =
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

proc getFromBuffer*(buff: string, T: typedesc, pos: var BiggestInt): T=
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