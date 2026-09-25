// .flat() of two literal arrays of 10: 20 items
const groups = [
  ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
  ["k", "l", "m", "n", "o", "p", "q", "r", "s", "t"],
];
await parallel(groups.flat().map((t) => () => agent(t)));
