// a backtick regex after a division and a comment (#2670 review, from r8-verify)
x = a / /*c*/ /[`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
x = a / /*c*/ /[`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
