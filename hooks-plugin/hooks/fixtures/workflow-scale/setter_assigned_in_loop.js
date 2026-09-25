// a setter a loop assigns (#2670 review, from r8-verify)
await parallel([() => agent("a"), () => agent("b"), () => agent("c"),
  async () => { const o = { set v(x) { agent("v") } }; for (const f of args.findings) o.v = f },
]);
