// an object method named catch, called by a loop (#2670 review, from r8-verify)
await parallel([() => agent("a"), () => agent("b"), () => agent("c"),
  async () => { const o = { catch() { return agent("v") } }; for (const f of args.findings) await o.catch() },
]);
