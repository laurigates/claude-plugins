// a helper that calls its parameter 12 times
async function retry(fn) {
  for (let i = 0; i < 12; i++) await fn();
}
await retry(() => agent("a"));
