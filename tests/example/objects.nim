type ComplexObject* = object
  a*, b*: float
  c: string

proc initComplexObject*: ComplexObject = ComplexObject(a: 30, b: 400, c: "Hello")