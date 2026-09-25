// Array(n) with n a const: 14 slots
const n = 14;
await Promise.all(Array(n).fill(0).map(() => agent("x")));
