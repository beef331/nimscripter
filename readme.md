# Nimscripter
Nimscripter is enables easy interop between Nim and Nimscript for realtime scriptable applications.

[Video Explanation](https://www.youtube.com/watch?v=GXBxvtHDjbg)
## How to use
Install Nimscripter with Nimble then create a .nim file and .nims file.

Make a folder entitled `stdlib` and copy copy all Nim files you wish to ship as a stdlib from Nim's stdlib and or any of your own files.`system.nim` and the `system` folder are required, but you can copy any other pure libraries and ship them, though they're only usable if they support Nimscript. If you use choosenim you can find the the Nim stdlib to copy from inside `~/.choosenim/toolchains/nim-version/lib`.
```nim
#Below is code to be  in the .nim file
import nimscripted #Where the macros come from
proc doThing(): int {.exportToScript.} = 42 #Will create a `doThing` proc in Nimscript
import nimscripter #Must appear after any wanted nimscript procs
let intr = loadScript("script.nims")
```
```nim
#Code below is inside the Nimscript file
assert doThing() == 42
```
When compiled with `-d:scripted` the assertion will be ran and no issue found.

Compiling with `-d:debugScript` will output the constructed Nimscript for easier debugging in expansion of this package.

### Calling code from Nim
Inside Nimscript the `exportToNim` macro can be applied to procs to enable calling from Nim, the following code will demonstrate how. The name of the proc to call has "Exported" appended to it
```nim
#.nim file below
import nimscripter
let intr = loadscript("script.nims")
var buf = ""
10.addToBuffer(buff)
if intr.isSome:
  intr.get.invoke("fancyStuffExported", [buf.toPnode], void) #Void is the return type
```
```nim
#Nimscript file
proc fancyStuff(a: int) {.exportToNim}= assert a == 10
```

### Appending Code To Nimscript
You can either write modules to import or use the `exportCode` macro to send code to Nimscript. The code is included as is to Nimscript and not ran in Nim.
```nim
#.nim file
exportCode:
  type Awbject = object
    a, b, c: int

  proc `+`(a, b: Awbject): Awbject =
    result.a = a.a + b.a
    result.b = a.b + b.b
    result.c = a.c + b.c
```
```nim
#Nimscript file
var 
  one = Awbject(a: 10, b: 20, c: 30)
  two = Awbject(a: 12, b: 15, c: 52)
assert Awbject(a: 22, b: 35, c: 82) == one + two
