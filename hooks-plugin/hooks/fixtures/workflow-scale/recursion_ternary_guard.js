// a ternary guard bounds the depth: f(13) down to 0, 14 entries
const f = (n) => {
  agent("r" + n);
  return n > 0 ? f(n - 1) : 0;
};
f(13);
