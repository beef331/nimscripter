type ComplexObject* = object
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

