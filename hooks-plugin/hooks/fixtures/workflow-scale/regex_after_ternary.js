// a backtick regex after ? (#2670 review, from r7-verify)
x = a ? /[`]/ : 1;
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
x = a ? /[`]/ : 1;
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
