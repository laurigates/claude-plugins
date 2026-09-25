// Array(n) with n assigned 14: unbounded, never below the 14 it was given
let n = 2;
n = 14;
await Promise.all(Array(n).fill(0).map(() => agent("x")));
