import compiler / [renderer, vmdef]

type
  VmProcSignature* = object
    name*: string
    vmRunImpl*: string
    vmProc*: proc(args: VmArgs){.closure, gcsafe.}
