// filter hands its elements on: each thunk runs once per pass of the outer loop
const fns = [() => agent("a"), () => agent("b"), () => agent("c")];
for (let pass = 0; pass < 4; pass++) {
  for (const f of fns.filter((f) => typeof f === "function")) await f();
}
