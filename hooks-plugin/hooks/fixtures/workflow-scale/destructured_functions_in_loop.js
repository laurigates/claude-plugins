// functions bound by array and object destructuring, called 3 times each
const [run] = [(f) => agent("v")];
const { go } = { go: (f) => agent("w") };
for (let i = 0; i < 3; i++) {
  await run(i);
  await go(i);
}
