import compiler / [renderer, vmdef]

type
  VmProcSignature* = object
    vmCompDefine*: string
    vmRunDefine*: string
    name*: string
    compName*: string
    vmProc*: proc(args: VmArgs){.closure, gcsafe.}
