// a recursive function around the call (#2670 review, from r8-verify)
async function go(n) { if (n <= 0) return; await parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")]); await go(n - 1); }
await go(8);
