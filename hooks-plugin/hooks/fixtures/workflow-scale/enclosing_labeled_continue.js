// a labeled loop with continue around the call (#2670 review, from r8-verify)
outer: for (const f of args.findings) { await parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")]); continue outer; }
