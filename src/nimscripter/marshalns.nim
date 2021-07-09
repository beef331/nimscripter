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
