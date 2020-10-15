import src/awbject
import json
for x in 0..10:
  fire(x, 32f, 6421f)
cry(false, "")
cry(true, "You're a god damn wimp")
kill($(%Awbject(a: 300)))

#Above nimscript interacts with the below Nim code,
#without any manual interop(aside from json conversion)
#[
  proc fire(damage: int, x, y: float32){.scripted.}=
  echo damage, " ", x, " ", y

  proc cry(doCry: bool, message: string){.scripted.}=
    if doCry: echo message
    else: echo "You are not sad"

  proc kill(a: Awbject){.scripted.}=
    echo a.a

]#
