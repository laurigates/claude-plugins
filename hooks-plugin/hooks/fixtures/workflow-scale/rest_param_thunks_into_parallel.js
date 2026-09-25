// thunks taken through a rest parameter and handed to parallel(): each runs once
// (#2670 round 10; round 9 read every argument after the rest slot as never called: 8)
const inParallel = (...tasks) => parallel(tasks);
await inParallel(() => agent("t0"), () => agent("t1"), () => agent("t2"), () => agent("t3"), () => agent("t4"), () => agent("t5"), () => agent("t6"), () => agent("t7"), () => agent("t8"), () => agent("t9"), () => agent("t10"), () => agent("t11"));
