import nimscripter, nimscripter/variables
import std/unittest
import std/[strutils, pegs]

suite "case object tests":

  test("test peg"):
    const script = NimScriptFile dedent"""
    import pegs
    let testPeg* = peg"'hello'"
    """
    let intr = loadScript(script)
    getGlobalNimsVars intr:
      testPeg: Peg
    check $testPeg == "'hello'"
