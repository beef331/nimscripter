import std/tables
export tables
type
  ComplexObject* = object
    someInt*: int
    case someBool*: bool
    of true:
      someString*: string
      case secondaryBool*: bool
      of true:
        someOtherString*: string
      else: discard
    else:
      someIntTwo*: int
  SomeRef* = ref object
    a*: int
  SomeEnum* {.pure.} = enum
    a, b, c, d
  SomeVarObject* = ref object
    case kind*: SomeEnum
    of a:
      b*: float
    of d:
      c*: int
    else:
      d*: string
  RecObject* = ref object
    next*: RecObject
    b*: Table[string, string]