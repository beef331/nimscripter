import nimscripter, nimscripter/variables
import std/unittest
addVariable(myImpl, productName, string)
addVariable(myImpl, doJump, bool)
addVariable(myImpl, appId, int)
const
  scriptProcs = implNimScriptModule(myImpl) # This emits our exported code
  ourScript = NimScriptFile"""
productName = "bbb"
doJump = productName == "bbb"
appId = 300
"""

suite "Variable addins":
  test "Ensure assignment works":
    let intr = loadScript(ourScript, scriptProcs)
    check intr.getGlobalVariable[:string]("productName") == "bbb"
    check intr.getGlobalVariable[:bool]("doJump")
    check intr.getGlobalVariable[:int]("appId") == 300
