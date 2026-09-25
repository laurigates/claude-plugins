// an element handed to a named helper through forEach: 12 calls
const loop = (f) => {
  for (let i = 0; i < 12; i++) f();
};
const fs = [() => agent("a")];
fs.forEach(loop);
