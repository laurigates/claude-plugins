// a .map callback inside Promise.all (#2670 review, from r7-verify)
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"), () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"), () => agent("i"),
  () => Promise.all(args.findings.map((f) => agent("v " + f))),
]);
