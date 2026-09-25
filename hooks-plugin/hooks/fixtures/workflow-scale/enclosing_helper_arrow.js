// a const arrow a loop calls (#2670 review, from r8-verify)
const review = async (f) => parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")]);
for (const f of args.findings) await review(f);
