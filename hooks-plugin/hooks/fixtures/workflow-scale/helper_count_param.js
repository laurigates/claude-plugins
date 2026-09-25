// a helper's loop limit is a parameter a plain call passes 12
async function times(n, fn) {
  for (let i = 0; i < n; i++) await fn(i);
}
await times(12, (i) => agent("x" + i));
