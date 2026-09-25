// a reduce callback gets the array as its fourth parameter
const fns = [() => agent("a"), () => agent("b")];
fns.reduce((acc, _, i, a) => {
  for (const u of units) a[i](u);
  return acc;
}, 0);
