// filter(Boolean) calls no element; the kept element runs 12 times
const fs = [() => agent("a")];
const g = fs.filter(Boolean);
for (let i = 0; i < 12; i++) g[0]();
