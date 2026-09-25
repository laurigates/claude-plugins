// a backtick regex after a comma (#2670 review, from r7-verify)
f(1, /[`]/);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
f(1, /[`]/);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
