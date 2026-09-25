// a rest parameter whose elements an inline .map callback calls: once each
function runAll(label, ...fns) {
  return Promise.all(fns.map((fn) => fn()));
}
await runAll("x", () => agent("t0"), () => agent("t1"), () => agent("t2"), () => agent("t3"), () => agent("t4"), () => agent("t5"), () => agent("t6"), () => agent("t7"), () => agent("t8"), () => agent("t9"), () => agent("t10"), () => agent("t11"));
