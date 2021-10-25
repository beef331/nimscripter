import nimscripter
import std/unittest
suite "Readme Examples":
  test("Example 1"):
    proc doThing(): int = 42
    exportTo(myImpl, doThing) # The name of our "nimscript module" is `myImpl`
    const 
      scriptProcs = implNimScriptModule(myImpl) # This emits a list of our exported code
      ourScript = NimScriptFile"assert doThing() == 42" # Convert to `NimScriptFile` for loading from strings
    let intr = loadScript(ourScript, scriptProcs)
  test("Example 2"):
    const script = NimScriptFile"proc fancyStuff*(a: int) = assert a in [10, 300]" # Notice `fancyStuff` is exported
    let intr = loadScript(script, []) # We are not exposing any procedures hence `[]`
    intr.invoke(fancyStuff, 10) # Calls `fancyStuff(10)` in vm
    intr.invoke(fancyStuff, 300) # Calls `fancyStuff(300)` in vm
