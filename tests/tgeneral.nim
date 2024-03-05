import nimscripter
import nimscripter/[vmconversion, variables]
import example/objects
import std/[json, unittest, os]

suite("General A(fromFile)"):
  var compl: ComplexObject
  proc doStuff(a: ComplexObject) = compl = a
  proc doStuffA(a: SomeRef) = check a.a == 100
  proc doStuffB(a: seq[int]) = check a == @[10, 20, 30, 10, 50, 100]
  proc doThingWithDist(a: DistType) = check int(a) == 100
  proc testSink(i: sink int): int = i

  exportTo(test,
    doStuff,
    doStuffA,
    doStuffB,
    doThingWithDist,
    testSink,
    DistType,
    ComplexObject,
    SomeRef,
    RecObject,
    SomeEnum
  )
  const addins = implNimscriptModule(test)
  let intr = loadScript(NimScriptPath("tests/example/first.nims"), addins, modules = ["tables"])

  test("nums"):
    check intr.invoke(testDistinct, DistType(100), returnType = DistType).int == 100

    check intr.invoke(getuint8, 128u8, returnType = uint8) == 128u8
    check intr.invoke(getint8, -123i8, returnType = int8) == -123i8

    check intr.invoke(getuint16, 32131u16, returnType = uint16) == 32131u16
    check intr.invoke(getint16, -321i16, returnType = int16) == -321i16

    check intr.invoke(getuint32, 32131u32, returnType = uint32) == 32131u32
    check intr.invoke(getint32, -321i32, returnType = int32) == -321i32

    check intr.invoke(getuint64, 32131u64, returnType = uint64) == 32131u64
    check intr.invoke(getint64, -321i64, returnType = int64) == -321i64

    check intr.invoke(getfloat32, 3.1415926535f, returnType = float32) == 3.1415926535f
    check intr.invoke(getfloat, 42.424242, returnType = float64) == 42.424242

    check intr.invoke(getChar, 'a', returnType = char) == 'a'
    check intr.invoke(getbool, true, returnType = bool) == true
    check intr.invoke(getSomeEnum, a, returnType = SomeEnum) == a

    var myRefSeq = new seq[int]
    myRefSeq[] = @[10, 20, 30]

    check intr.invoke(getRefSeq, myRefSeq, returnType = typeof(myRefSeq))[] == myRefSeq[]
    myRefSeq = nil
    check intr.invoke(getRefSeq, myRefSeq, returnType = typeof(myRefSeq)).isNil
    check intr.invoke(getProc, proc(){.nimcall.} = discard, returnType = proc(){.nimcall.}).isNil

    type AnObject = ref object
      a, b: int
      when false:
        a, b: int
    let aVal = fromVm(AnObject, AnObject(a: 100, b: 20).toVm)
    check aVal.a == 100
    check aVal.b == 20

    type QueryParams = distinct seq[(string, string)] # Silly error due to mixins

    check compiles((discard fromVm(QueryParams, nil)))


  test("parseErrors"):
    expect(VMParseError):
      intr.invoke(getfloat, 3.14, returnType = SomeEnum)

    expect(VMParseError):
      intr.invoke(getUint64, 10u64, returnType = float)

    expect(VMParseError):
      intr.invoke(getChar, 'a', returnType = string)

    expect(VMParseError):
      discard intr.getGlobalVariable[:seq[int]]("a")

    expect(VMParseError):
      discard intr.getGlobalVariable[: (int, int)]("a")

  test("sets"):
    const
      charSet = {'a'..'z', '0'}
      byteSet = {0u8..32u8, 100u8..127u8}
      intSet = {range[355..357](355), 356}
      enumSet = {a, b, c}
    check intr.get.invoke(getCharSet, charSet, returnType = set[char]) == charSet
    check intr.get.invoke(getByteSet, byteSet, returnType = set[byte]) == byteSet
    check intr.get.invoke(getIntSet, intSet, returnType = set[355..357]) == intSet
    check intr.get.invoke(getEnumSet, enumSet, returnType = set[SomeEnum]) == enumSet

  test("colls"):
    const
      arr = [1, 2, 3, 4, 5]
      seq1 = @arr
      seq2 = @[3, 6, 8, 9, 10]
      str1 = "Hello"
      str2 = "world"
    check intr.invoke(getArray, arr, returnType = array[5, int]) == arr
    check intr.invoke(getSeq, seq1, returnType = seq[int]) == seq1
    check intr.invoke(getSeq, seq2, returnType = seq[int]) == seq2
    check intr.invoke(getString, str1, returnType = string) == str1
    check intr.invoke(getString, str2, returnType = string) == str2

  test("Object tests"):
    let res = intr.get.invoke(fromJson, returnType = JsonNode)
    check $res == """{"someInt":300,"someBool":true,"someString":"heel ya","secondaryBool":true,"someOtherString":"Really cool?"}"""
    intr.invoke(testObj, ComplexObject(someBool: false, someInt: 320, someintTwo: 42))
    intr.invoke(test, 10, 20d, returnType = void)
    intr.invoke(testTuple, ((100, 200), 200, 300, SomeRef(a: 300)))
    intr.invoke(recObj, RecObject(next: RecObject(), b: {"hello": "world"}.toTable))
    intr.invoke(testJson, %* compl)

suite("General B(fromstring)"):
  test("save / load state"):
    const file = "var someVal* = 52\nproc setVal* = someVal = 32"
    var intr = loadScript(NimScriptFile(file))

    check intr.getGlobalVariable[:int]("someVal") == 52
    intr.invoke(setVal)
    check intr.getGlobalVariable[:int]("someVal") == 32
    intr.loadScriptWithState(NimScriptFile(file))
    check intr.getGlobalVariable[:int]("someVal") == 32

  test("Dynamic invoke"):
    const script = NimScriptFile"proc fancyStuff*(a: int) = assert a in [10, 300]"
    let intr = loadScript(script)
    intr.get.invokeDynamic("fancyStuff", 10)

  test("Get global variables macro"):
    let script = NimScriptFile"""
let required* = "main"
let defaultValueExists* = "foo"
"""

    let intr = loadScript script

    getGlobalNimsVars intr:
      required: string
      optional: Option[string]
      defaultValue: int = 1
      defaultValueExists = "bar"

    check required == "main"
    check optional.isNone
    check defaultValue == 1
    check defaultValueExists == "foo"

test "Use Nimble":
  let nimblePath = getHomeDir() / ".nimble" / "pkgs"
  let intr = loadScript(NimscriptFile"", searchPaths = @[nimblePath])

import nimscripter/vmops
test "cmpic issue":
  const script = """
import std/os ## <-- this import
proc build*(): bool =
  assert getCurrentDir().lastPathPart == "nimscripter"
  true

when isMainModule:
  discard build()
  """
  addVmops(buildpackModule)
  addCallable(buildpackModule):
    proc build(): bool
  const addins = implNimscriptModule(buildpackModule)
  discard loadScript(NimScriptFile(script), addins)

test "Export complex variables":
  var
    objA = ComplexObject(
      someInt: -44,
      someBool: true,
      someString: "aaa",
      secondaryBool: true,
      someOtherString: "bbb"
    )
    objB = SomeVarObject(
      kind: SomeEnum.c,
      d: "somevar"
    )
    objC = RecObject(
      next: RecObject(
        next: RecObject(
          b: {"a":"A", "b":"B"}.toTable()
        )
      )
    )
    enumA = SomeEnum.c

  const script = """
assert objA.someInt == -44
assert objA.someBool == true
assert objA.someString == "aaa"
assert objA.secondaryBool == true
assert objA.someOtherString == "bbb"
assert enumA == SomeEnum.c
assert objB.kind == SomeEnum.c
assert objB.d == "somevar"
assert objC.next.next.b["a"] == "A"
assert objC.next.next.b["b"] == "B"
"""
  exportTo(objTestModule, SomeEnum, ComplexObject, SomeVarObject, RecObject, enumA, objA, objB, objC)
  const addins = implNimscriptModule(objTestModule)
  check loadScript(NimScriptFile(script), addins, modules=["std/tables"]).isSome


test "Ensure we cache intepreters for a direct call":
  const script = NimScriptFile"doThing(); proc fancyStuff*(a: int) = assert a == 10"
  var i = 0
  proc doThing() = inc i
  addCallable(myTest):
   proc fancyStuff(a: int)
  exportTo(
    myTest,
    doThing)
  const addins = implNimscriptModule(myTest)
  loadScript(script, addins).invoke(fancyStuff, 10)
  check i == 1
