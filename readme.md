# Nimscripter
Nimscripter is enables easy interop between Nim and Nimscript for realtime scriptable applications.

## How to use
Install Nimscripter(`nimble install nimscripter`) with Nimble then create a .nim file and .nims file.

```nim
import nimscripter
proc doThing(): int = 42
exportTo(myImpl, doThing) # The name of our "nimscript module" is `myImpl`
const 
  scriptProcs = implNimScriptModule(myImpl) # This emits a list of our exported code
  ourScript = NimScriptFile"assert doThing() == 42" # Convert to `NimScriptFile` for loading from strings
let intr = loadScript(ourScript, scriptProcs) # Load our script with our code and using our system `stdlib`(not portable)
```


### Calling code from Nim
Any exported non overloaded and non generic procedures can be called from Nim
```nim
  const script = NimScriptFile"proc fancyStuff*(a: int) = assert a in [10, 300]" # Notice `fancyStuff` is exported
  let intr = loadScript(script, []) # We are not exposing any procedures hence `[]`
  intr.invoke(fancyStuff, 10) # Calls `fancyStuff(10)` in vm
  intr.invoke(fancyStuff, 300) # Calls `fancyStuff(300)` in vm
```
### Using a custom/shipped stdlib

Make a folder entitled `stdlib` and copy all Nim files you wish to ship as a stdlib from Nim's stdlib and any of your own files.
`system.nim` and the `system` folder are required.
`You can copy any other pure libraries and ship them, though they're only usable if they support Nimscript.
`If you use choosenim you can find the the Nim stdlib to copy from inside `~/.choosenim/toolchains/nim-version/lib`.