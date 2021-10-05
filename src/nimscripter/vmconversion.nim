import std/[macros, macrocache, sugar, typetraits, importutils]
import compiler/[renderer, ast, idents]

proc toVm*[T: enum or bool](a: T): Pnode = newIntNode(nkIntLit, a.BiggestInt)
proc toVm*[T: char](a: T): Pnode = newIntNode(nkUInt8Lit, a.BiggestInt)

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

proc toVm*[T: float32](a: T): Pnode = newFloatNode(nkFloat32Lit, BiggestFloat(a))
proc toVm*[T: float64](a: T): Pnode = newFloatNode(nkFloat64Lit, BiggestFloat(a))
proc toVm*[T: string](a: T): PNode = newStrNode(nkStrLit, a)
proc toVm*[T: seq](obj: T): PNode
proc toVm*[T: tuple](obj: T): PNode
proc toVm*[T: object](obj: T): PNode
proc toVm*[T: ref object](obj: T): PNode

proc extractType(typ: NimNode): NimNode =
  let impl = typ.getTypeInst
  impl[^1]

proc fromVm*(t: typedesc[SomeOrdinal], node: PNode): t =
  if node.kind == nkExprColonExpr:
    t(node[1].intVal)
  else:
    t(node.intVal)

proc fromVm*(t: typedesc[SomeFloat], node: PNode): t =
  if node.kind == nkExprColonExpr:
    t(node[1].floatVal)
  else:
    t(node.floatVal)

proc fromVm*(t: typedesc[string], node: PNode): string =
  if node.kind == nkExprColonExpr:
    node[1].strVal
  else:
    node.strVal

proc fromVm*[T: object](obj: typedesc[T], vmNode: PNode): T
proc fromVm*[T: tuple](obj: typedesc[T], vmNode: Pnode): T
proc fromVm*[T: ref object](obj: typedesc[T], vmNode: PNode): T

proc fromVm*[T](obj: typedesc[seq[T]], vmNode: Pnode): seq[T] =
  result.setLen(vmNode.sons.len)
  for i, x in vmNode.sons:
    result[i] = fromVm(T, x)

proc fromVm*[T: tuple](obj: typedesc[T], vmNode: Pnode): T =
  var index = 0
  for x in result.fields:
    x = fromVm(typeof(x), vmNode[index])
    inc index

proc hasRecCase(n: NimNode): bool =
  for son in n:
    if son.kind == nnkRecCase:
      return true

proc baseSym(n: NimNode): NimNode =
  if n.kind == nnkSym:
    n
  else:
    n.basename

proc addFields(n: NimNode, fields: var seq[NimNode]) =
  case n.kind
  of nnkRecCase:
    fields.add n[0][0].baseSym
  of nnkIdentDefs:
    for def in n[0..^3]:
      fields.add def.baseSym
  else:
    discard

proc parseObject(body, vmNode, baseType: NimNode, offset: var int, fields: var seq[
    NimNode]): NimNode =
  ## Emits the VmNode -> Object constructor so the function can be called

  template stmtlistAdd(body: NimNode) =
    if result.kind == nnkNilLit:
      result = body
    elif result.kind != nnkStmtList:
      result = newStmtList(result, body)
    else:
      result.add body

  template addConstr(n: NimNode) =
    if not n.hasRecCase:
      let colons = collect(newSeq):
        for x in fields:
          let desymd = ident($x)
          nnkExprColonExpr.newTree(desymd, desymd)
      if result.kind == nnkNilLit:
        result = newStmtList()
      let constr = nnkObjConstr.newTree(baseType)
      constr.add colons
      stmtlistAdd(constr)

  case body.kind
  of nnkRecList:
    for defs in body:
      defs.addFields(fields)
    for defs in body:
      stmtlistAdd parseObject(defs, vmNode, baseType, offset, fields)
    if body.len == 0 or body[0].kind notin {nnkNilLit, nnkDiscardStmt}:
      addConstr(body)
  of nnkIdentDefs:
    let typ = body[^2]
    for def in body[0..^3]:
      let name = ident($def.baseSym)
      stmtlistAdd quote do:
        let `name` = fromVm(typeof(`typ`), `vmNode`[`offset`][1])
      inc offset
  of nnkRecCase:
    let
      descrimName = ident($body[0][0].baseSym)
      typ = body[0][1]
    stmtlistAdd quote do:
      let `descrimName` = fromVm(typeof(`typ`), `vmNode`[`offset`][1])

    inc offset
    let caseStmt = nnkCaseStmt.newTree(descrimName)
    let preFieldSize = fields.len
    for subDefs in body[1..^1]:
      caseStmt.add parseObject(subDefs, vmNode, baseType, offset, fields)
    stmtlistAdd caseStmt
    fields.setLen(preFieldSize)
  of nnkOfBranch, nnkElifBranch:
    let
      conditions = body[0]
      preFieldSize = fields.len
      ofBody = parseObject(body[1], vmNode, baseType, offset, fields)
    stmtlistAdd body.kind.newTree(conditions, ofBody)
    fields.setLen(preFieldSize)
  of nnkElse:
    let preFieldSize = fields.len
    stmtlistAdd nnkElse.newTree(parseObject(body[0], vmNode, baseType, offset, fields))
    fields.setLen(preFieldSize)
  of nnkNilLit, nnkDiscardStmt:
    result = newStmtList()
    addConstr(result)
  else: discard

proc parseObject(body, vmNode, baseType: NimNode, offset: var int): NimNode =
  var fields: seq[NimNode]
  result = parseObject(body, vmNode, baseType, offset, fields)


proc toPnode(body, obj, vmNode: NimNode, offset: var int): NimNode =
  ## Emits a constructor based off the type, works for variants and normal objects

  template stmtlistAdd(body: NimNode) =
    if result.kind == nnkNilLit:
      result = body
    elif result.kind != nnkStmtList:
      result = newStmtList(result, body)
    else:
      result.add body

  case body.kind
  of nnkRecList:
    for defs in body:
      stmtlistAdd toPnode(defs, obj, vmNode, offset)
    if body.len == 0:
      stmtlistAdd nnkDiscardStmt.newTree(newEmptyNode())
  of nnkIdentDefs:
    for def in body[0..^3]:
      let name = ident($def.baseSym)
      stmtlistAdd quote do:
        `vmNode`[`offset`] = newNode(nkExprColonExpr)
        `vmNode`[`offset`].add newNode(nkEmpty)
        `vmNode`[`offset`].add toVm(`obj`.`name`)
      inc offset
  of nnkRecCase:
    let descrimName = ident($body[0][0].baseSym)
    stmtlistAdd quote do:
      `vmNode`[`offset`] = newNode(nkExprColonExpr)
      `vmNode`[`offset`].add newNode(nkEmpty)
      `vmNode`[`offset`].add toVm(`obj`.`descrimName`)

    inc offset
    let caseStmt = nnkCaseStmt.newTree(newDotExpr(obj, descrimName))
    for subDefs in body[1..^1]:
      caseStmt.add toPnode(subDefs, obj, vmNode, offset)
    stmtlistAdd caseStmt
  of nnkOfBranch:
    let
      conditions = body[0]
      ofBody = toPnode(body[1], obj, vmNode, offset)
    stmtlistAdd body.kind.newTree(conditions, ofBody)
  of nnkElse:
    stmtlistAdd nnkElse.newTree(toPnode(body[0], obj, vmNode, offset))
  of nnkNilLit:
    stmtlistAdd nnkDiscardStmt.newTree(newEmptyNode())
  else: discard

proc replaceGenerics(n: NimNode, genTyp: seq[(NimNode, NimNode)]) =
  for i in 0 ..< n.len:
    var x = n[i]
    if x.kind in {nnkSym, nnkIdent}:
      for (name, typ) in genTyp:
        if x.eqIdent(name):
          n[i] = typ
    else:
      replaceGenerics(x, genTyp)

macro fromVmImpl[T: object](obj: typedesc[T], vmNode: PNode): untyped =
  let
    typ = newCall(ident"typeof", obj)
    recList = block:
      let extracted = obj.extractType
      if extracted.len > 0:
        let
          impl = extracted[0].getImpl
          recList = extracted[0].getImpl[^1][^1].copyNimTree
          genParams = collect(newSeq):
            for i, x in impl[1]:
              (x, extracted[i + 1])
        recList.replaceGenerics(genParams)
        recList
      else:
        extracted.getImpl[^1][^1]
  var offset = 1
  result = newStmtList(newCall(bindSym"privateAccess", typ)):
    parseObject(recList, vmNode, typ, offset)

proc getRefRecList(n: NimNode): NimNode =
  if n.len > 0:
    let
      impl = n[0].getImpl
      recList = n[0].getImpl[^1][^1].copyNimTree
      genParams = collect(newSeq):
        for i, x in impl[1]:
          (x, n[i + 1])
    recList.replaceGenerics(genParams)
    result = recList
  else:
    let recList = n.getImpl[^1][^1]
    if recList.kind == nnkSym:
      result = recList.getTypeImpl[^1]
    else:
      result = recList[^1]

macro fromVmImpl[T: ref object](obj: typedesc[T], vmNode: PNode): untyped =
  let
    typ = extractType(obj)
    recList = getRefRecList(typ)
    typConv = newCall(ident"typeof", typ)
  var offset = 1
  result = newStmtList(newCall(bindSym"privateAccess", typConv)):
    parseObject(recList, vmNode, typ, offset)
  result = quote do:
    if `vmNode`.kind == nkNilLit:
      default(`typConv`)
    else:
      `result`

proc fromVm*[T: object](obj: typedesc[T], vmNode: PNode): T = fromVmImpl(obj, vmnode)
proc fromVm*[T: ref object](obj: typedesc[T], vmNode: PNode): T = fromVmImpl(obj, vmnode)

proc toVm*[T: seq](obj: T): PNode =
  result = newNode(nkBracketExpr)
  for x in obj:
    result.add toVm(x)

proc toVm*[T: tuple](obj: T): PNode =
  result = newNode(nkTupleConstr)
  for x in obj.fields:
    result.add toVm(x)

macro toVMImpl[T: object](obj: T): PNode =
  let
    pnode = genSym(nskVar, "node")
    recList = obj.getTypeImpl[^1]
  result = newStmtList()
  result.add quote do:
    privateAccess(typeof(`obj`))
    var `pnode` = newNode(nkObjConstr)
  var offset = 1
  result.add toPnode(recList, obj, pnode, offset)
  result.add pnode
  for x in 0..offset:
    result.insert 1 + x, quote do:
      `pnode`.add newNode(nkEmpty)

proc toVm*[T: object](obj: T): PNode = toVMImpl(obj)

macro toVMImpl[T: ref object](obj: T): PNode =
  let pnode = genSym(nskVar, "node")
  var recList = obj.getTypeImpl[^1]
  if recList.kind == nnkSym:
    reclist = recList.getTypeImpl[^1]
  result = newStmtList()
  result.add quote do:
    privateAccess(typeof(`obj`))
    var `pnode` = newNode(nkObjConstr)
  var offset = 1
  result.add toPnode(recList, obj, pnode, offset)
  result.add pnode
  for x in 0..<offset:
    result.insert 1, quote do:
      `pnode`.add newNode(nkEmpty)

proc toVm*[T: ref object](obj: T): PNode =
  if obj.isNil:
    newNode(nkNilLit)
  else:
    toVMImpl(obj)
