// a rest parameter after the element collects the index and the array; what it
// reaches is not followed, so each element is costed at ASSUMED calls, not 0
const fns = [() => agent("a"), () => agent("b")];
fns.forEach((f, ...more) => {
  for (let k = 0; k < 6; k++) more[1][0]();
});
