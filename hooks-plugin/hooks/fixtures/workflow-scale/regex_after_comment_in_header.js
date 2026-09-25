// a backtick regex after a header holding a comment (#2670 review, from r7-verify)
if (a /* ) */ && b) /[`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
if (a /* ) */ && b) /[`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
