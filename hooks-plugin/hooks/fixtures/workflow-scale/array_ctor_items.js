// Array(a, b, ...) with more than one argument holds them: 12
await Promise.all(Array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12).map(() => agent("x")));
