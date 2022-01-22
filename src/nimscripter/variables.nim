import std/[macros, options], nimscripter,
    compiler/nimeval

type SomeInterpreter = Option[Interpreter] or Interpreter

using intr: SomeInterpreter

macro getSubType(T: typedesc[Option]): untyped =
  getTypeInst(T)[1][1]

proc tryGetGlobalVariable[T](intr; name: string): T =
  when T is Option:
    try:
      getGlobalVariable[getSubType(T)](intr, name).some
    except VmSymNotFound:
      none getSubType(T)
  else:
    getGlobalVariable[T](intr, name)

macro getWithDefault(intr; name: untyped; defaultValue: typed) =
  ## This is a hack to make the defaultValue a typed argument.
  ## It is needed to be able to use `getType`
  let
    nameStr = $name
    ttype = getType defaultValue
  quote do:
    let `name` = tryGetGlobalVariable[Option[`ttype`]](`intr`, `nameStr`).get(`defaultValue`)

macro getGlobalNimsVars*(intr; varDefs: untyped) =
  ## Allows you to define variables that should be populated from a nimscript
  ## Usage:
  ##  getGlobalNimsVars(intr):
  ##    varName: string # required variable
  ##    varNameOpt: Option[string] # optional variable
  ##    varNameDef = "default" # optional variable with default value
  # echo varDefs.treeRepr
  vardefs.expectKind nnkStmtList
  result = newStmtList()
  for def in varDefs:
    case def.kind:
    of nnkAsgn:
      # <name> = <defaultValue>
      let
        name = def[0]
        defaultValue = def[1]

      result.add quote do:
        getWithDefault(`intr`, `name`, `defaultValue`)
    of nnkCall:
      # <name>:<rhs>
      let
        name = def[0]
        nameStr = $name
        rhs = def[1][0] # Whatever comes after ':'. Could include assignment

      case rhs.kind:
      of nnkAsgn:
        # <name>: <type> = <defaultValue>
        let defaultValue = rhs[1]
        result.add quote do:
          getWithDefault(`intr`, `name`, `defaultValue`)
      else:
        # <name>: <type>
        let ttype = rhs
        result.add quote do:
          let `name` = tryGetGlobalVariable[`ttype`](`intr`, `nameStr`)
    else: continue
