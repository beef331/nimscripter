import nimscripter
import example/objects
import std/[json, unittest]
suite("General A(fromFile)"):
  var compl: ComplexObject
  proc doStuff(a: ComplexObject) = compl = a
  proc doStuffA(a: SomeRef) = check a.a == 100
  proc doStuffB(a: seq[int]) = check a == @[10, 20, 30, 10, 50, 100]

  exportTo(test,
    doStuff,
    doStuffA,
    doStuffB,
    ComplexObject,
    SomeRef,
    RecObject,
    SomeEnum
  )
  const addins = implNimscriptModule(test)
  let intr = loadScript(NimScriptPath("tests/example/first.nims"), addins, modules = ["tables"])

  test("nums"):
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

  test("parseErrors"):
    expect(VMParseError):
      intr.invoke(getfloat, 3.14, returnType = SomeEnum)

    expect(VMParseError):
      intr.invoke(getUint64, 10u64, returnType = float)

    expect(VMParseError):
      intr.invoke(getChar, 'a', returnType = string)

    expect(VMParseError):
      discard intr.getGlobalVariable[: seq[int]]("a")

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

    check intr.getGlobalVariable[: int]("someVal") == 52
    intr.invoke(setVal)
    check intr.getGlobalVariable[: int]("someVal") == 32
    intr.loadScriptWithState(NimScriptFile(file))
    check intr.getGlobalVariable[: int]("someVal") == 32