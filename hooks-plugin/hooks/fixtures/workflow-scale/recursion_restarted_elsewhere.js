// g calls f(3) again from inside the recursion, so f's depth is not proven: 16
let restarts = 3;
async function f(n) {
  await agent("f" + n);
  if (n > 0) await f(n - 1);
  else if (restarts-- > 0) await g();
}
async function g() {
  await f(3);
}
await f(3);
