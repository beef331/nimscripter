import nimscripter/macros
proc multiplyBy10(a: int): int {.exportToScript: multiply.} = a * 10
