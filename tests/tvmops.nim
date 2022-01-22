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