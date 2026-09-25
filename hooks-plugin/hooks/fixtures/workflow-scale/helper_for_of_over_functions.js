// a helper that calls each function of an array it is passed
async function all(fns) {
  for (const fn of fns) await fn();
}
await all([() => agent("a"), () => agent("b")]);
