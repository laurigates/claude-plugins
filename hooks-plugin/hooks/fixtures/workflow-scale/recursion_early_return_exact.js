// an early return after the work bounds the depth: f(0) up to 11, 12 entries
function f(n) {
  agent("r" + n);
  if (n >= 11) return;
  f(n + 1);
}
f(0);
