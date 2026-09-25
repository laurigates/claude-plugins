// a default-parameter function the body calls 20 times
async function go(fn = () => agent("d")) {
  for (let i = 0; i < 20; i++) await fn();
}
await go();
