import nimscripter
import std/[strscans, strutils, parseutils, os, times, strformat, linenoise, terminal]
import packages/docutils/highlite


type 
  RenderMode = enum
    astRender, codeRender

  RenderSetting = enum
    showIndex
    useColor

  ColoredToken = enum
    operator, keyword, ident, strlit, numlit

  ColoredCode = distinct string

  RenderSettings = set[RenderSetting]

  AstNode = ref object
    name: string
    value: string
    children: seq[AstNode]
    parent: AstNode

var
  renderMode = astRender
  renderSettings: RenderSettings
  indexColor = fgGreen
  nameColors = (fgWhite, fgWhite)
  tokenColors = [
    operator: fgYellow,
    keyword: fgRed,
    ident: fgBlue,
    strLit: fgGreen,
    numLit: fgCyan
  ]


proc addName(s: var string, name: string, depth: int) =
  if useColor in renderSettings:
    s.add:
      ansiForegroundColorCode:
        if depth mod 2 == 0:
          nameColors[0]
        else:
          nameColors[1]
  s.add name
  if useColor in renderSettings:
    s.add ansiResetCode

proc addIndex(s: var string, index: int) =
  if useColor in renderSettings:
    s.add ansiForegroundColorCode(indexColor)
  s.add fmt"[{index}]"

  if useColor in renderSettings:
    s.add ansiResetCode

proc toString(ast: AstNode, depth, index: int): string =
  result = repeat("  ", depth.Natural)
  result.addName(ast.name, depth)
  if ast.value.len > 0:
    result.add &", {ast.value}"

  if showIndex in renderSettings and depth > 0:
    result.addIndex(index)

  result.add "\n"
  for i, x in ast.children:
    result.add x.toString(depth + 1, i)

proc `$`(ast: AstNode): string =
  for i, x in ast.children:
    result.add x.toString(0, i)

proc renderAst(s: string): AstNode =
  new result
  var
    indent = 0
    presentNode = result
  for line in s.splitLines:
    let
      start = skipWhitespace(line)
      newIndent = start div 2
      line = line[start..^1]

    var name, value: string

    if newIndent < indent:
      for _ in 0..<abs(newIndent - indent):
        presentNode = presentNode.parent
    if indent < newIndent:
      presentNode = presentNode.children[^1]

    if line.scanf("$+$s$+", name, value):
      presentNode.children.add AstNode(name: name, value: value, parent: presentNode)
    elif line.scanf("$+", name):
      presentNode.children.add AstNode(name: name, parent: presentNode)
    indent = newIndent

proc renderCode(s: ColoredCode) =
  let s = string(s)
  var toknizr: GeneralTokenizer
  initGeneralTokenizer(toknizr, s)
  template writeColored(color: ColoredToken) =
    stdout.write ansiForegroundColorCode(tokenColors[color])
    stdout.write substr(s, toknizr.start, toknizr.length + toknizr.start - 1)
    stdout.write ansiResetCode

  while true:
    getNextToken(toknizr, langNim)
    case toknizr.kind
    of gtEof: break  # End Of File (or string)
    of gtOperator:
      writeColored operator
    of gtStringLit:
      writeColored strlit
    of gtDecNumber .. gtFloatNumber:
      writeColored numlit
    of gtKeyWord:
      writeColored keyword
    of gtIdentifier:
      writeColored ident
    else:
      stdout.write substr(s, toknizr.start, toknizr.length + toknizr.start - 1)
  stdout.flushFile

proc renderCode(s: string) =
  var offset = 0
  for i, ch in s:
    if ch notin Whitespace:
      offset = i
      break
  if offset > 0:
    echo s[offset .. ^1]
  else:
    echo s


proc recieveData(codeRepr, astRepr: string) =
  clearScreen()
  setCursorPos(0, 0)
  case renderMode:
  of astRender:
    echo renderAst(astRepr)
  of codeRender:
    if useColor in renderSettings:
      renderCode(ColoredCode(codeRepr))
    else:
      renderCode(codeRepr)

proc setIndexColor(col: ForegroundColor) = indexColor = col
proc setColors(col: (ForegroundColor, ForegroundColor)) = nameColors = col

proc setRenderSettings(settings: RenderSettings) =
  renderSettings = settings

proc setRenderMode(mode: RenderMode) = renderMode = mode

exportTo(macrosport,
  recieveData,
  RenderSetting,
  RenderSettings,
  setRenderSettings,
  ForegroundColor,
  setIndexColor,
  setColors,
  RenderMode,
  setRenderMode
  )

const additions = implNimscriptModule(macrosport)
let filePath = paramStr(1)
try:
  var intr: Option[Interpreter]
  var lastMod: Time
  while true:
    let currMod = getLastModificationTime(filePath)
    if lastMod < currMod:
      lastMod = currMod
      intr.safeloadScriptWithState(NimScriptPath(filePath), additions, modules = ["macrosports"])


    sleep(10) # TODO Use selectors

except Exception as e:
  echo e.msg
