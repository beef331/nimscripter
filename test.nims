type A = object
  x,y: float32
type B = object
  a: int
  b: A

let b = B(a: 100, b: A(x: 3.3210f, y: 1.321321f))

var 
  buf = ""
  pos: BiggestInt = 0
b.addToBuffer(buf)
echo getFromBuffer(buf, B, pos)