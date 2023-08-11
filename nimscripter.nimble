# Package

version = "1.1.2"
author        = "Jason Beetham"
description   = "A easy to use Nimscript interop package"
license       = "MIT"
srcDir        = "src"


# Dependencies
requires "nim >= 1.6.0" # need some bug fixes
requires "https://github.com/disruptek/assume >= 0.7.1"


task buildLib, "Builds the library":
  selfExec("c --app:lib -d:release -d:nimscripterlib --nimMainPrefix:\"nimscripter_\" ./src/nimscripter/nimscr.nim")
task buildLibd, "Builds the library":
  selfExec("c --app:lib -d:nimscripterlib --nimMainPrefix:\"nimscripter_\" ./src/nimscripter/nimscr.nim")
