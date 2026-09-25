// an element spread into plain parameters may land at any of them: charged the
// most any is called, 12
const loop = (f) => {
  for (let i = 0; i < 12; i++) f();
};
const fs = [() => agent("a")];
loop(...fs);
