// a recursion the text bounds: go(11) steps n down by 1 while n > 0, 12 entries
async function go(n) {
  await agent("r" + n);
  if (n > 0) await go(n - 1);
}
await go(11);
