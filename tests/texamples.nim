import nimscripter
import std/unittest
suite "Readme Examples":
  test("Example 1"):
    proc doThing(): int = 42
    exportTo(myImpl, doThing) # The name of our "nimscript module" is `myImpl`
    const 
      scriptProcs = implNimScriptModule(myImpl) # This emits our exported code
      ourScript = NimScriptFile("assert doThing() == 42") # Convert to `NimScriptFile` for loading from strings
    let intr = loadScript(ourScript, scriptProcs) # Load our script with our code and using our system `stdlib`(not portable)
  test("Example 2"):
    const script = NimScriptFile"proc fancyStuff*(a: int) = assert a in [10, 300]" # Notice `fancyStuff` is exported
    let intr = loadScript(script) # We are not exposing any procedures hence single parameter
    intr.invoke(fancyStuff, 10) # Calls `fancyStuff(10)` in vm
    intr.invoke(fancyStuff, 300) # Calls `fancyStuff(300)` in vm
