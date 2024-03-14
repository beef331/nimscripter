
task genHeader, "Genrates the header":
  selfExec("c -c --app:lib --warning:UnsafeDefault:off -d:genHeader --nimMainPrefix:\"nimscripter_\" ./src/nimscripter/nimscr.nim")

task buildLib, "Builds the library":
  selfExec("c --app:lib -d:release --nimMainPrefix:\"nimscripter_\" --outDir:./ ./src/nimscripter/nimscr.nim")

task buildLibd, "Builds the library":
  selfExec("c --app:lib -d:nimscripterlib --nimMainPrefix:\"nimscripter_\" --outDir:./ --debugger:native -d:useMalloc ./src/nimscripter/nimscr.nim")
