import nimscripter
import nimscripter/expose
import example/objects
proc doStuff(a: ComplexObject){.exportToScript: test.} = echo a

const testProc = implNimscriptModule(test)
let intr = loadScript("tests/example/first.nims", testProc, modules = ["objects"])