// a for...of around the whole parallel([...]) call (#2670 review, from r8-verify)
for (const f of args.findings) { await parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")]); }
