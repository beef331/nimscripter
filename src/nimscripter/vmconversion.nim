import std/[macros, macrocache, typetraits]
import "$nim"/compiler/[renderer, ast, idents]
import assume/typeit

type
  VMParseError* = object of CatchableError ## Error raised when an object cannot be parsed.

proc toVm*[T: enum or bool](a: T): Pnode = newIntNode(nkIntLit, a.BiggestInt)
proc toVm*[T: char](a: T): Pnode = newIntNode(nkUInt8Lit, a.BiggestInt)

proc toVm*[T: int8](a: T): Pnode = newIntNode(nkInt8Lit, a.BiggestInt)
proc toVm*[T: int16](a: T): Pnode = newIntNode(nkInt16Lit, a.BiggestInt)
proc toVm*[T: int32](a: T): Pnode = newIntNode(nkInt32Lit, a.BiggestInt)
proc toVm*[T: int64](a: T): Pnode = newIntNode(nkint64Lit, a.BiggestInt)
proc toVm*[T: int](a: T): Pnode = newIntNode(nkIntLit, a.BiggestInt)

proc toVm*[T: uint8](a: T): Pnode = newIntNode(nkuInt8Lit, a.BiggestInt)
proc toVm*[T: uint16](a: T): Pnode = newIntNode(nkuInt16Lit, a.BiggestInt)
proc toVm*[T: uint32](a: T): Pnode = newIntNode(nkuInt32Lit, a.BiggestInt)
proc toVm*[T: uint64](a: T): Pnode = newIntNode(nkuint64Lit, a.BiggestInt)
proc toVm*[T: uint](a: T): Pnode = newIntNode(nkuIntLit, a.BiggestInt)

proc toVm*[T: float32](a: T): Pnode = newFloatNode(nkFloat32Lit, BiggestFloat(a))
proc toVm*[T: float64](a: T): Pnode = newFloatNode(nkFloat64Lit, BiggestFloat(a))
proc toVm*[T: string](a: T): PNode = newStrNode(nkStrLit, a)
proc toVm*[T: proc](a: T): PNode = newNode(nkNilLit)

proc toVm*[T](s: set[T]): PNode =
  result = newNode(nkCurly)
  let count = high(T).ord - low(T).ord
  result.sons.setLen(count)
  for val in s:
    let offset = val.ord - low(T).ord
    result[offset] = toVm(val)

proc toVm*[T: openArray](obj: T): PNode
proc toVm*[T: tuple](obj: T): PNode
proc toVm*[T: object](obj: T): PNode
proc toVm*[T: ref](obj: T): PNode
proc toVm*[T: distinct](a: T): PNode = toVm(distinctBase(T, true)(a))


template raiseParseError(t: typedesc): untyped =
  raise newException(VMParseError, "Cannot convert to: " & $t)

const intLits = {nkCharLit..nkUInt64Lit}
proc fromVm*(t: typedesc[SomeOrdinal or char], node: PNode): t =
  if node.kind in intLits:
    t(node.intVal)
  else:
    raiseParseError(t)

proc fromVm*(t: typedesc[SomeFloat], node: PNode): t =
  if node.kind in nkFloatLiterals:
    t(node.floatVal)
  else:
    raiseParseError(t)

proc fromVm*(t: typedesc[string], node: PNode): string =
  if node.kind in {nkStrLit, nkTripleStrLit, nkRStrLit}:
    node.strVal
  else:
    raiseParseError(t)

proc fromVm*[T](t: typedesc[set[T]], node: Pnode): t =
  if node.kind == nkCurly:
    for val in node.items:
      if val != nil:
        case val.kind
        of nkRange:
          for x in fromVm(T, val[0])..fromVm(T, val[1]):
            result.incl x
        else:
          result.incl fromVm(T, val)
  else:
    raiseParseError(set[T])

proc fromVm*(t: typedesc[proc]): typeof(t) = nil

proc fromVm*[T: object](obj: typedesc[T], vmNode: PNode): T
proc fromVm*[T: tuple](obj: typedesc[T], vmNode: Pnode): T
proc fromVm*[T: ref object](obj: typedesc[T], vmNode: PNode): T
proc fromVm*[T: ref(not object)](obj: typedesc[T], vmNode: PNode): T

proc fromVm*[T: proc](obj: typedesc[T], vmNode: PNode): T = nil

proc fromVm*[T: distinct](obj: typedesc[T], vmNode: PNode): T = T(fromVm(distinctBase(T, true), vmNode))

proc fromVm*[T](obj: typedesc[seq[T]], vmNode: Pnode): seq[T] =
  if vmNode.kind in {nkBracket, nkBracketExpr}:
    result.setLen(vmNode.sons.len)
    for i, x in vmNode.pairs:
      result[i] = fromVm(T, x)
  else:
    raiseParseError(seq[T])

proc fromVm*[Idx, T](obj: typedesc[array[Idx, T]], vmNode: Pnode): obj =
  if vmNode.kind in {nkBracket, nkBracketExpr}:
    for i, x in vmNode.pairs:
      result[Idx(i - obj.low.ord)] = fromVm(T, x)
  else:
    raiseParseError(array[Idx, T])

proc fromVm*[T: tuple](obj: typedesc[T], vmNode: Pnode): T =
  if vmNode.kind == nkTupleConstr:
    var index = 0
    for x in result.fields:
      x = fromVm(typeof(x), vmNode[index])
      inc index
  else:
    raiseParseError(T)

proc replaceGenerics(n: NimNode, genTyp: seq[(NimNode, NimNode)]) =
  ## Replaces all instances of a typeclass with a generic type,
  ## used in generated headers for the VM.
  for i in 0 ..< n.len:
    var x = n[i]
    if x.kind in {nnkSym, nnkIdent}:
      for (name, typ) in genTyp:
        if x.eqIdent(name):
          n[i] = typ
    else:
      replaceGenerics(x, genTyp)

proc fromVm*[T: object](obj: typedesc[T], vmNode: PNode): T =
  if vmNode.kind == nkObjConstr:
    var ind = 1
    typeIt(result, {titAllFields, titDeclaredOrder}):
      if it.isAccessible:
        {.cast(uncheckedAssign).}:
          it = fromVm(typeof(it), vmNode[ind][1])
      inc ind
  else:
    raiseParseError(T)

proc fromVm*[T: ref object](obj: typedesc[T], vmNode: PNode): T =
  case vmNode.kind
  of nkNilLit:
    result = nil
  of nkObjConstr:
    new result
    result[] = fromVm(typeof(result[]), vmNode)
  else:
    raiseParseError(T)

proc fromVm*[T: ref(not object)](obj: typedesc[T], vmNode: PNode): T =
  if vmNode.kind != nkNilLit:
    new result
    result[] = fromVm(typeof(result[]), vmNode)

proc toVm*[T: openArray](obj: T): PNode =
  result = newNode(nkBracketExpr)
  for x in obj:
    result.add toVm(x)

proc toVm*[T: tuple](obj: T): PNode =
  result = newNode(nkTupleConstr)
  for x in obj.fields:
    result.add toVm(x)

proc toVm*[T: object](obj: T): PNode =
  result = newNode(nkObjConstr)
  result.add newNode(nkEmpty)
  typeit(obj, {titAllFields}):
    result.add newNode(nkEmpty)
  var i = 1
  typeIt(obj, {titAllFields, titDeclaredOrder}):
    if it.isAccessible:
      result[i] = newNode(nkExprColonExpr)
      result[i].add newNode(nkEmpty)
      result[i].add toVm(it)
    inc i

proc toVm*[T: ref](obj: T): PNode =
  if obj.isNil:
    newNode(nkNilLit)
  else:
    toVM(obj[])
