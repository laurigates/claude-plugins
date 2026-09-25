// a helper that reaches its argument through `arguments`: costed at ASSUMED, not 0
function runAll() {
  for (let i = 0; i < 8; i++) arguments[0]();
}
runAll(() => agent("t"));
