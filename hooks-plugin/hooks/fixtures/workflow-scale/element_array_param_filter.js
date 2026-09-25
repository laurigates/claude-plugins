// a .filter callback calls elements through the array parameter
const fns = [() => agent("a"), () => agent("b")];
const kept = fns.filter((_, i, a) => {
  for (const u of units) a[i](u);
  return true;
});
