// a backtick regex after a block's } (#2670 review, from r7-verify)
{ }
/[`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
{ }
/[`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
