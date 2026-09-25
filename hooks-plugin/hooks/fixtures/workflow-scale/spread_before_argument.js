// an argument after a spread lands where the spread's runtime length puts it, so it
// is costed at ASSUMED; round 9 read it as the parameter at its written index (b: 0)
async function run(a, b, task) {
  await task();
}
const pre = [1, 2];
await run(...pre, () => agent("t"));
