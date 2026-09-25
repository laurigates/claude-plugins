// a generator yields once per pass of its 12-pass loop; the spread holds 12
function* g() {
  for (let i = 0; i < 12; i++) yield i;
}
await Promise.all([...g()].map(() => agent("x")));
