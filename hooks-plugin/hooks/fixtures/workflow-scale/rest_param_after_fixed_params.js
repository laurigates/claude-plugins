// a rest parameter after two plain ones, iterated by for...of: each thunk runs once
const runAll = async (a, b, ...fns) => {
  await a();
  await b();
  for (const f of fns) await f();
};
await runAll(() => agent("t0"), () => agent("t1"), () => agent("t2"), () => agent("t3"), () => agent("t4"), () => agent("t5"), () => agent("t6"), () => agent("t7"), () => agent("t8"), () => agent("t9"), () => agent("t10"), () => agent("t11"));
