// .apply spreads its array into the helper's parameters; b runs 12 times
function run(a, b) {
  for (let i = 0; i < 12; i++) b();
}
run.apply(null, [() => log("x"), () => agent("b")]);
