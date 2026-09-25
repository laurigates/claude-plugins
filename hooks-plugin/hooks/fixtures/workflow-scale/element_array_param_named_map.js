// a named array's .map callback calls elements through the array parameter
const fns = [() => agent("a"), () => agent("b")];
fns.map((_, i, all) => {
  for (const u of units) all[i](u);
});
