// a for await...of around the call (#2670 review, from r8-verify)
for await (const f of args.findings) { await parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")]); }
