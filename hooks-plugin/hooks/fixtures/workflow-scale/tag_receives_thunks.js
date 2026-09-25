// a template tag receives its substitutions as arguments and calls each: 12
// (#2670 round 10; round 9 costed a function inside a template at 0)
const run = (strings, ...fns) => Promise.all(fns.map((f) => f()));
await run`${() => agent("t0")} ${() => agent("t1")} ${() => agent("t2")} ${() => agent("t3")} ${() => agent("t4")} ${() => agent("t5")} ${() => agent("t6")} ${() => agent("t7")} ${() => agent("t8")} ${() => agent("t9")} ${() => agent("t10")} ${() => agent("t11")}`;
