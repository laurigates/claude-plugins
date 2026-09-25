// KNOWN GAP: an array grown by index in a 12-pass loop costs ASSUMED (8)
const L = [1, 2];
for (let i = 0; i < 12; i++) L[i] = i;
await parallel(L.map((c) => () => agent("w")));
