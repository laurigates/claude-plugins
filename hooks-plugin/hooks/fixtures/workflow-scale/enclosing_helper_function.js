// a function declaration a loop calls (#2670 review, from r8-verify)
async function review(f) { await parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")]); }
for (const f of args.findings) await review(f);
