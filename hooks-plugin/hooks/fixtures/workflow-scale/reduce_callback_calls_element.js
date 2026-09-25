// a reduce callback gets the element as its second parameter: each thunk runs twice
const fns = [() => agent("a"), () => agent("b"), () => agent("c")];
fns.reduce((acc, f) => {
  f();
  f();
  return acc + 1;
}, 0);
