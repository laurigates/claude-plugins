// a while loop inside an element (#2670 review, from r7-verify)
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"), () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"), () => agent("i"),
  async () => { let i = 0; while (i < args.findings.length) { await agent("v" + i); i++ } },
]);
