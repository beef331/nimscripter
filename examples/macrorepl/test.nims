import std/macros
setRenderSettings({showIndex, useColor})
setColors (fgRed, fgGreen)
setIndexColor(fgCyan)
setRenderMode(codeRender)

macro doStuff(a: int): untyped =
  result = newStmtList()
  for x in 0..a.intVal:
    result.add newCall("echo", newLit(x))

template doStufff() =
  echo "hello world"


typedRepl(doStuff(3))