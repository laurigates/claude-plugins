// an arrow declared and called once per pass of a 3-item loop: 3, not 9
for (const f of [1, 2, 3]) {
  const run = () => agent(f);
  await run();
}
