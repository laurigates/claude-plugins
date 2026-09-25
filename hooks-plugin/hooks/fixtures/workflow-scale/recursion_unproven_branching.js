// two calls per entry, stopped by a counter that is not a parameter: the depth
// is not proven, so the tree is ASSUMED levels deep (1 + 2 + ... + 2^8 = 511)
let budget = 20;
async function walk() {
  await agent("w");
  if (budget-- > 0) {
    await walk();
    await walk();
  }
}
await walk();
