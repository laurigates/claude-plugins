// an arrow stored in an object property, called by a later .map (#2670 review, from r7-verify)
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"), () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"), () => agent("i"),
  async () => { const o = { run: (f) => agent("v " + f) }; return Promise.all(args.findings.map((f) => o.run(f))) },
]);
