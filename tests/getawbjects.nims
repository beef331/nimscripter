proc getAwbjects(): seq[Awbject] {.exportToNim.}=
  result.add Awbject(a: 100, b: @[10f32, 30, 3.1415], name: "Steve")
  result.add Awbject(a: 42, b: @[6.28f32], name: "Tau is better")
  result.add Awbject()