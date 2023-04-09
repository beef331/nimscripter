# Nimscripter
Nimscripter is enables easy interop between Nim and Nimscript for realtime scriptable applications.

## How to use
First create a `config.nims` with `--path:"$nim"` in your project to use the Nim compiler api. This uses the local compiler version rather than the Nimble compiler package. 

Next install Nimscripter(`nimble install nimscripter`) with Nimble then create a .nim file with the following.

```nim
import nimscripter
proc doThing(): int = 42
exportTo(myImpl, doThing) # The name of our "nimscript module" is `myImpl`
const 
  scriptProcs = implNimScriptModule(myImpl) # This emits our exported code
  ourScript = NimScriptFile("assert doThing() == 42") # Convert to `NimScriptFile` for loading from strings
let intr = loadScript(ourScript, scriptProcs) # Load our script with our code and using our system `stdlib`(not portable)
```

Note that `exportTo` can take in multiple procedures, types, or global variables at once.

```nim
proc doThing(): int = 42
var myGlobal = 30
type MyType = enum
  a, b, c
exportTo(myImpl,
  doThing
  myGlobal,
  myType)
```

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

One may extract global variables from a nimscript file using a convenience macro.

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

### Keeping state inbetween loads

`loadScriptWithState` will load a script, if it loads a valid script it will reset any global exported variables in the script with their preload values.

`safeloadScriptWithState` will attempt to load a script keeping global state, if it fails it does not change the interpeter, else it'll load the script and set it's state to the interpreters.

`saveState`/`loadState` can be used to manually manage the state inbetween loaded scripts.

### VmOps

A subset of the nimscript interopped procedures are available inside `nimscripter/vmops`.
If you feel a new op should be added feel free to PR it.
```nim
import nimscripter
import nimscripter/vmops

const script = """
proc build*(): bool =
  echo "building nim... "
  echo getCurrentDir()
  echo "done"
  true

when isMainModule:
  discard build()
"""
addVmops(buildpackModule)
addCallable(buildpackModule):
  proc build(): bool
const addins = implNimscriptModule(buildpackModule)
discard loadScript(NimScriptFile(script), addins)
```

### Using a custom/shipped stdlib

Make a folder entitled `stdlib` and copy all Nim files you wish to ship as a stdlib from Nim's stdlib and any of your own files.
`system.nim` and the `system` folder are required.
`You can copy any other pure libraries and ship them, though they're only usable if they support Nimscript.
`If you use choosenim you can find the the Nim stdlib to copy from inside `~/.choosenim/toolchains/nim-version/lib`.
When using a custom search paths add the root file only, if you provide more than that it will break modules.

### Overriding the error hook

The error hook can be overridden for more behaviour like showing the error in the program,
the builtin error hook is as follows:
```nim
proc errorHook(config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) {.gcsafe.} =
  if severity == Error and config.error_counter >= config.error_max:
    var fileName: string
    for k, v in config.m.filenameToIndexTbl.pairs:
      if v == info.fileIndex:
        fileName = k
    echo "Script Error: $1:$2:$3 $4." % [fileName, $info.line, $(info.col + 1), msg]
    raise (ref VMQuit)(info: info, msg: msg)
```
