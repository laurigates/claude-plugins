// a helper called through .call passes its arguments from the second on: 20
function times(n, fn) {
  for (let i = 0; i < n; i++) fn(i);
}
times.call(null, 20, (i) => agent("x" + i));
