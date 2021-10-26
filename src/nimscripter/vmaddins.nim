import compiler / [renderer, vmdef]

type
  VmProcSignature* = object
    name*: string
    vmRunImpl*: string
    vmProc*: proc(args: VmArgs){.closure, gcsafe.}
  VMAddins* = object
    procs*: seq[VmProcSignature]
    additions*: string
    postCodeAdditions*: string