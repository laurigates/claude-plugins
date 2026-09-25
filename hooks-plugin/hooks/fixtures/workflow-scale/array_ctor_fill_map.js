// new Array(12) has 12 slots; fill and map keep them
await parallel(new Array(12).fill(0).map((_, i) => () => agent("x" + i)));
