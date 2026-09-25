// two calls per entry while d < 3, from rec(0): 1 + 2 + 4 + 8 = 15
async function rec(d) {
  await agent("r" + d);
  if (d < 3) await Promise.all([rec(d + 1), rec(d + 1)]);
}
await rec(0);
