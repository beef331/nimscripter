import std/json
import hooks
echo %*{"a": "Hello World"}
proc doThing*(): int =
  echo "Huh"
  result = 30
proc doOtherThing*(a: int): string = $a
proc arrTest*(arr: openArray[int]): bool =
  echo arr
  arr == [0, 1, 2, 3, 4]
testInput(200)
