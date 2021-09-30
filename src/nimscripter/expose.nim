import std/[macros, macrocache, sugar, typetraits, importutils]
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
  deSymd.repr


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
        var `idnt` = fromVm(typeof(`typ`), getNode(`vmArgs`, `argNum`))
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

proc fromVm*[T: object or tuple](obj: typedesc[T], vmNode: PNode): T
proc fromVm*[T: ref object](obj: typedesc[T], vmNode: PNode): T


macro fromVmImpl[T: seq](obj: typedesc[T], vmNode: Pnode): untyped =
  let typ = extractType(obj)
  result = quote do:
    var res: `typ`
    res.setLen(`vmNode`.sons.len)
    for i, x in `vmNode`.sons:
      res[i] = fromVm(typeof(res[0]), x)
    res

proc fromVm*[Y; T: seq[Y]](obj: typedesc[T], vmNode: Pnode): seq[Y] = fromVmImpl(obj, vmnode)


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
  ## Emits a constructor based off the type, works for variants and normal objects

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
        let `name` =
          if `vmNode`.kind == nkTupleConstr:
            fromVm(typeof(`typ`), `vmNode`[`offset` - 1])
          elif `vmNode`.kind == nkObjConstr:
            fromVm(typeof(`typ`), `vmNode`[`offset`])
          else:
            fromVm(typeof(`typ`), `vmNode`)
      inc offset
  of nnkRecCase:
    let
      descrimName = ident($body[0][0].baseSym)
      typ = body[0][1]
    stmtlistAdd quote do:
      let `descrimName` =
        if `vmNode`.kind == nkTupleConstr:
          fromVm(typeof(`typ`), `vmNode`[`offset` - 1])
        elif `vmNode`.kind == nkObjConstr:
          fromVm(typeof(`typ`), `vmNode`[`offset`][1])
        else:
          fromVm(typeof(`typ`), `vmNode`)
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

proc replaceGenerics(n: NimNode, genTyp: seq[(NimNode, NimNode)]) =
  for i in 0 ..< n.len:
    var x = n[i]
    if x.kind in {nnkSym, nnkIdent}:
      for (name, typ) in genTyp:
        if x.eqIdent(name):
          n[i] = typ
    else:
      replaceGenerics(x, genTyp)

macro fromVmImpl[T: object or tuple](obj: typedesc[T], vmNode: PNode): untyped =
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
    for i, x in `vmNode`:
      if x.kind == nkExprColonExpr:
        for y in x:
          echo i, y.kind
    if `vmNode`.kind == nkNilLit:
      default(`typConv`)
    else:
      `result`
  echo result.repr
proc fromVm*[T: object or tuple](obj: typedesc[T], vmNode: PNode): T = fromVmImpl(obj, vmnode)
proc fromVm*[T: ref object](obj: typedesc[T], vmNode: PNode): T = fromVmImpl(obj, vmnode)

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

