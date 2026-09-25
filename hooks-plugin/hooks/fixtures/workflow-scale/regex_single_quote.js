// a regex holding a single quote (#2670 review, from r7-verify)
x = /[']/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
x = /[']/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
