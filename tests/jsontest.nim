import std/json
import nimscripter
import nimscripter/expose
import compiler/nimeval

proc echoJson(j: JsonNode){.exportToScript: jsontest.} = echo j.pretty()
const
  jsonModule = implNimscriptModule(jsontest)
  stdlib = findNimStdlibCompileTime()
let intr = loadScript("tests/example/jsonscript.nims", jsonModule, modules = ["json"], stdpath = stdlib)