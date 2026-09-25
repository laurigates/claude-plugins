// a while loop around the call (#2670 review, from r8-verify)
let i = 0; while (i < args.findings.length) { i++; await parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")]); }
