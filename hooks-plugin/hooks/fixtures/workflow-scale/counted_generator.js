// a generator yielding one agent() per pass of its own 12-pass loop
function* gen() {
  for (let i = 0; i < 12; i++) yield agent("x");
}
for (const p of gen()) await p;
