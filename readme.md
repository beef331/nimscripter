# Nimscripter
Nimscripter is enables easy interop between Nim and Nimscript for realtime scriptable applications.

## How to use
Install Nimscripter(`nimble install nimscripter`) with Nimble then create a .nim file with the following.

```nim
import nimscripter
proc doThing(): int = 42
exportTo(myImpl, doThing) # The name of our "nimscript module" is `myImpl`
const 
  scriptProcs = implNimScriptModule(myImpl) # This emits our exported code
  ourScript = NimScriptFile("assert doThing() == 42") # Convert to `NimScriptFile` for loading from strings
let intr = loadScript(ourScript, scriptProcs) # Load our script with our code and using our system `stdlib`(not portable)
```

You also may need to create a `config.nims` with `--path:"$nim"` for the compiler api to work.

### Calling code from Nim
Any exported non overloaded and non generic procedures can be called from Nim
```nim
const script = NimScriptFile"proc fancyStuff*(a: int) = assert a in [10, 300]" # Notice `fancyStuff` is exported
let intr = loadScript(script) # We are not exposing any procedures hence single parameter
intr.invoke(fancyStuff, 10) # Calls `fancyStuff(10)` in vm
intr.invoke(fancyStuff, 300) # Calls `fancyStuff(300)` in vm
```

The above works but does not impose any safety on the VM code, to do that the following can be done
```nim
addCallable(test3):
  proc fancyStuff(a: int) # Has checks for the nimscript to ensure it's definition doesnt change to something unexpected.
const
  addins = implNimscriptModule(test3)
  script = NimScriptFile"proc fancyStuff*(a: int) = assert a in [10, 300]" # Notice `fancyStuff` is exported
let intr = loadScript(script, addins) # This adds in out checks for the proc
intr.invoke(fancyStuff, 10) # Calls `fancyStuff(10)` in vm
intr.invoke(fancyStuff, 300) # Calls `fancyStuff(300)` in vm
```

### Getting global variables from nimscript

You may extract global variables from a nimscript file using a convenience macro.

```nim
import nimscripter, nimscripter/variables

let script = NimScriptFile"""
let required* = "main"
let defaultValueExists* = "foo"
"""
let intr = loadScript script

getGlobalNimsVars intr:
  required: string # required variable
  optional: Option[string] # optional variable
  defaultValue: int = 1 # optional variable with default value
  defaultValueExists = "bar" # You may omit the type if there is a default value

check required == "main"
check optional.isNone
check defaultValue == 1
check defaultValueExists == "foo"

```
Basic types are supported, such as string, int, bool, etc..


### Exporting code verbatim
`nimscriptr/expose` has `exportCode` and `exportCodeAndKeep` they both work the same, except the latter keeps the code so it can be used inside Nim.
```nim
exportCode(nimScripter):
 proc doThing(a, b: int) = echo a, " ", b # This runs on nimscript if called there
```


### Using a custom/shipped stdlib

Make a folder entitled `stdlib` and copy all Nim files you wish to ship as a stdlib from Nim's stdlib and any of your own files.
`system.nim` and the `system` folder are required.
`You can copy any other pure libraries and ship them, though they're only usable if they support Nimscript.
`If you use choosenim you can find the the Nim stdlib to copy from inside `~/.choosenim/toolchains/nim-version/lib`.
