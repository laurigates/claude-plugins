// a helper's while limit is a parameter whose default is 12
async function retry(fn, tries = 12) {
  let k = 0;
  while (k < tries) {
    await fn();
    k++;
  }
}
await retry(() => agent("x"));
