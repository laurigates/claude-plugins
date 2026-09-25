// a negative start over a list's length: 8 items from -5 is 13 passes
const xs = [1, 2, 3, 4, 5, 6, 7, 8];
for (let i = -5; i < xs.length; i++) await agent("x" + i);
