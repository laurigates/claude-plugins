// each invocation calls every element through the array parameter: 2 x 2 x 8
const run = (...fns) =>
  fns.forEach((f, i, arr) => {
    for (const u of units) arr.forEach((g) => g(u));
  });
run((u) => agent(u), (u) => agent(u));
