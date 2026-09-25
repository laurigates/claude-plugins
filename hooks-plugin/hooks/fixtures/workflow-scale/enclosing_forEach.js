// a forEach callback around the call (#2670 review, from r8-verify)
await Promise.all(args.findings.map(async () => 0)); for (const q of [0]) {}
const ps = []; args.findings.forEach((f) => ps.push(parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")]))); await Promise.all(ps);
