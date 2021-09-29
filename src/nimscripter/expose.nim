import std/[macros, macrocache, sugar]
import compiler/[renderer, ast, vmdef, vm, ast]
import procsignature
export VmProcSignature

func deSym*(n: NimNode): NimNode =
  # Remove all symbols
  result = n
  for x in 0 .. result.len - 1:
    if result[x].kind == nnkSym:
      result[x] = ident($result[x])
    else:
      result[x] = result[x].deSym

func getMangledName*(pDef: NimNode): string =
  ## Generates a close to type safe name for backers
  result = $pdef[0]
  for def in pDef[3][1..^1]:
    for idnt in def[0..^3]:
      result.add $idnt
    if def[^2].kind in {nnkSym, nnkIdent}:
      result.add $def[^2]
  result.add "Comp"

func getVmRuntimeImpl*(pDef: NimNode): string =
  ## Returns the nimscript code that will convert to string and return the value.
  ## This does the interop and where we want a serializer if we ever can.
  let deSymd = deSym(pDef.copyNimTree())
  deSymd[^1] = nnkDiscardStmt.newTree(newEmptyNode())

  result = deSymd.repr


proc getLambda*(pDef: NimNode): NimNode =
  ## Generates the lambda for the vm backed logic.
  ## This is what the vm calls internally when talking to Nim
  let
    vmArgs = ident"vmArgs"
    args = ident"args"
    pos = ident"pos"
    tmp = quote do:
      proc n(`vmArgs`: VmArgs){.closure, gcsafe.} = discard

  tmp[^1] = newStmtList()

  tmp[0] = newEmptyNode()
  result = nnkLambda.newNimNode()
  tmp.copyChildrenTo(result)

  var procArgs: seq[NimNode]
  for def in pDef.params[1..^1]:
    let typ = def[^2]
    for idnt in def[0..^3]: # Get data from buffer in the vm proc
      let
        idnt = ident($idnt)
        argNum = procArgs.len
      procArgs.add idnt
      result[^1].add quote do:
        var `idnt` = fromVm(type(`typ`), getNode(`vmArgs`, `argNum`))
  if pdef.params.len > 1:
    result[^1].add newCall(pDef[0], procArgs)

const procedureCache = CacheTable"NimscriptProcedures"

macro exportToScript*(moduleName: untyped, procedure: typed): untyped =
  result = procedure
  moduleName.expectKind(nnkIdent)
  block add:
    for name, _ in procedureCache:
      if name == $moduleName:
        procedureCache[name].add procedure
        break add
    procedureCache[$moduleName] = nnkStmtList.newTree(procedure)

macro implNimscriptModule*(moduleName: untyped): untyped =
  moduleName.expectKind(nnkIdent)
  result = nnkBracket.newNimNode()
  for p in procedureCache[$moduleName]:
    let
      runImpl = getVmRuntimeImpl(p)
      lambda = getLambda(p)
      realName = $p[0]
    result.add quote do:
      VmProcSignature(
        name: `realName`,
        vmRunImpl: `runImpl`,
        vmProc: `lambda`
      )

proc fromVm*(t: typedesc[SomeOrdinal], node: PNode): t =
  assert node.kind in nkCharLit..nkUInt64Lit
  return node.intVal.t

proc fromVm*(t: typedesc[SomeFloat], node: PNode): t =
  assert node.kind in nkFloatLit..nkFloat128Lit
  node.floatVal.t

proc fromVm*(t: typedesc[string], node: PNode): string =
  assert node.kind == nkStrLit
  node.strVal

proc parseObject(body, vmNode, typ: NimNode, offset: var int): NimNode =
  ## Emits a constructor based off the type, works for variants and normal objects
  result = newStmtList()
  for defs in body:
    case defs.kind
    of nnkIdentDefs:
      for def in defs[1..^3]:
        let
          name = def.basename
          typ = defs[^2]
        result.add quote do:
          let `name` = fromVm(`typ`, `vmNode`.getNode(`offset`))
        inc offset
    of nnkRecCase:
      let
        descrimName = defs[0][0].basename
        typ = defs[0][1]
      result.add quote do:
        let `descrimName` = fromVm(`typ`, `vmNode`.getNode(`offset`))
      inc offset
    of nnkOfBranch, nnkElifBranch:
      let
        conditions = defs[0]
        ofBody = parseObject(defs[1], vmNode, typ, offset)
      result.add defs.kind.newTree(conditions, ofBody)
    of nnkElse:
      result.add nnkElse.newTree(parseObject(defs[0], vmNode, typ, offset))
    else: discard

  echo result.repr

proc toPnode(body, obj, vmNode: NimNode, fields: seq[NimNode], offset: var int, descrims: seq[
    NimNode]): NimNode =
  ## Emits a constructor based off the type, works for variants and normal objects
  var
    fields = fields # Copy since we're adding to this
    descrims = descrims

  var descrimInd = -1
  for i, x in body:
    case x.kind
    of nnkIdentDefs:
      for field in x[0..^3]:
        let strField = newLit($field)
        fields.add quote do: # Add the field parse to fields
          let
            n = newNode(nkExprColonExpr)
            ident = PIdent(s: `strField`)
          n.add newIdentNode(ident, unknownLineInfo)
          n.add `obj`.`field`.toVm
          `vmNode`.add n
        inc offset
    of nnkRecCase:
      assert descrimInd == -1, "Presently this only supports a single descrim per indent"
      descrimInd = i
    else: discard

  if descrimInd >= 0:
    # This is a descriminat emit case stmt
    let
      recCase = body[descrimInd]
      discrim = recCase[0][0]
      name = $discrim
      descrimConv = quote do: # Emit a conversion for the descrim
        let
          n = newNode(nkExprColonExpr)
          ident = PIdent(s: `name`)
        n.add newIdentNode(ident, unknownLineInfo)
        n.add `obj`.`discrim`.toVm
        `vmNode`.add n

    inc offset
    descrims.add descrimConv
    result = newStmtList(nnkCaseStmt.newTree(newDotExpr(obj, discrim)))
    for node in recCase[1..^1]:
      let node = node.copyNimTree
      node[^1] = node[^1].toPnode(obj, vmNode, fields, offset, descrims) # Replace typdef with conversion
      result[^1].add node # Add to case statement
  else:
    result = newStmtList(descrims)
    result.add fields

proc extractType(typ: NimNode): NimNode =
  let impl = typ.getTypeInst
  impl[^1]

macro fromVm*[T: object](obj: typedesc[T], vmNode: PNode): untyped =
  let recList = obj[0].getImpl[^1][^1]
  var offset = 1
  result = newBlockStmt(parseObject(recList, vmNode, obj[0], offset))
  result = newStmtList(newCall(ident"privateAccess", obj[0]), result)

macro fromVm*[T: ref object](obj: typedesc[T], vmNode: PNode): untyped =
  let
    obj = extractType(obj)
  let
    recList =
      if obj.getImpl[^1][0].kind == nnkSym:
        obj.getImpl[^1][0].getImpl
      else:
        obj.getImpl[^1][0][^1]
    typ = obj
  var offset = 1
  result = newBlockStmt(parseObject(recList, vmNode, typ, offset))
  result = newStmtList(newCall(ident"privateAccess", newCall("typeof", typ)), result)
  result = quote do:
    if `vmNode`.kind == nkNilLit:
      `typ`(nil)
    else:
      `result`
  echo result.repr

macro fromVm*[T: seq](obj: typedesc[T], vmNode: Pnode): untyped =
  let
    typ = obj[0]
    elTyp = typ[^1]
  quote do:
    var res = newSeq[`elTyp`](`vmNode`.sons.len)
    for i, x in `vmNode`.sons:
      res[i] = fromVm(type(`elTyp`), x)
    res

proc toVm*[T: enum](a: T): Pnode = newIntNode(nkIntLit, a.ord.BiggestInt)
proc toVm*[T: bool](a: T): Pnode = newIntNode(nkIntLit, a.ord.BiggestInt)
proc toVm*[T: char](a: T): Pnode = newIntNode(nkUInt8Lit, a.ord.BiggestInt)

proc toVm*[T: int8](a: T): Pnode = newIntNode(nkInt8Lit, a)
proc toVm*[T: int16](a: T): Pnode = newIntNode(nkInt16Lit, a)
proc toVm*[T: int32](a: T): Pnode = newIntNode(nkInt32Lit, a)
proc toVm*[T: int64](a: T): Pnode = newIntNode(nkint64Lit, a)
proc toVm*[T: int](a: T): Pnode = newIntNode(nkIntLit, a)

proc toVm*[T: uint8](a: T): Pnode = newIntNode(nkuInt8Lit, a)
proc toVm*[T: uint16](a: T): Pnode = newIntNode(nkuInt16Lit, a)
proc toVm*[T: uint32](a: T): Pnode = newIntNode(nkuInt32Lit, a)
proc toVm*[T: uint64](a: T): Pnode = newIntNode(nkuint64Lit, a)
proc toVm*[T: uint](a: T): Pnode = newIntNode(nkuIntLit, a)

proc toVm*[T: float32](a: T): Pnode = newFloatNode(nkFloat32Lit, a)
proc toVm*[T: float64](a: T): Pnode = newFloatNode(nkFloat64Lit, a)

proc toVm*[T: string](a: T): PNode = newStrNode(nkStrLit, a)


macro toVM*[T: object](obj: T): PNode =
  let
    pnode = genSym(nskVar, "node")
    recList = obj.getTypeImpl[^1]
  result = newStmtList()
  result.add quote do:
    var `pnode` = newNode(nkObjConstr)
  var offset = 0
  result.add toPnode(recList, obj, pnode, @[], offset, @[])
  result.add pnode
  result = newBlockStmt(result)
  echo result.repr

