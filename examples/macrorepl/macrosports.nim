import std/macros
macro untypedRepl*(body: untyped) =
  newCall("recieveData", newLit(body.repr), newLit(body.treeRepr))

macro typedRepl*(body: typed) =
  newCall("recieveData", newLit(body.repr), newLit(body.treeRepr))