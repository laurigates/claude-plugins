// a thunk a .map returns, indexed and called by a loop (#2670 review, from r8-verify)
await parallel([() => agent("a"), () => agent("b"), () => agent("c"),
  async () => { const h = [0].map(function () { return () => agent("v") }); for (const f of args.findings) await h[0]() },
]);
