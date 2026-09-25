// a class method named catch, called by a loop (#2670 review, from r8-verify)
await parallel([() => agent("a"), () => agent("b"), () => agent("c"),
  async () => { class K { catch() { return agent("v") } }; const k = new K(); for (const f of args.findings) await k.catch() },
]);
