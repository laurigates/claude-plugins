// the array parameter spread into a new array and indexed still reaches every element
const fns = [() => agent("a"), () => agent("b")];
fns.forEach((_, i, arr) => {
  for (const u of units) [...arr][i](u);
});
