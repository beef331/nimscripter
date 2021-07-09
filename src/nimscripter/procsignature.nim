import compiler / [renderer, vmdef]

type
  VmProcSignature* = object
    vmStringImpl*: string
    vmStringName*: string
    vmRunImpl*: string
    realName*: string
    vmProc*: proc(args: VmArgs){.closure, gcsafe.}
