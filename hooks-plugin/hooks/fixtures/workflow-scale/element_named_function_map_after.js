// a function declaration passed to a later .map (#2670 review, from r7-verify)
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"), () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"), () => agent("i"),
  async () => { function go(f) { return agent("v " + f) } return Promise.all(args.findings.map(go)) },
]);
