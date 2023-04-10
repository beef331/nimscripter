import nimscripter, nimscripter/variables
import std/unittest
import std/[strutils, pegs]

suite "case object tests":

  test("test peg"):
    const script = NimScriptFile dedent"""
    import pegs
    let testPeg* = peg"'hello'"
    """ # Notice `fancyStuff` is exported
    let intr = loadScript(script) # We are not exposing any procedures hence single parameter
    # let p1: Peg = intr.invoke(fancyStuff, returnType = Peg) # Calls `fancyStuff(10)` in vm
    # echo "p1: ", $p1
    getGlobalNimsVars intr:
      testPeg: Peg
    
    echo "testPeg: ", $testPeg
  