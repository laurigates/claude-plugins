// a backtick regex after typeof (#2670 review, from r7-verify)
x = typeof /[`]/;
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
x = typeof /[`]/;
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
