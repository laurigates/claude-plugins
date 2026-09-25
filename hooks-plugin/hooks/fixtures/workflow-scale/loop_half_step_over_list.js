// a 0.5 step over a list's length is divided by: 7 items, 14 passes (+1)
const xs = [1, 2, 3, 4, 5, 6, 7];
for (let i = 0; i < xs.length; i += 0.5) await agent("x" + i);
