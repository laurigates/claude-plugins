// a parenthesized arrow a later loop calls (#2670 review, from r7-verify)
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"), () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"), () => agent("i"),
  async () => { const go = ((f) => agent("v " + f)); for (const f of args.findings) await go(f) },
]);
