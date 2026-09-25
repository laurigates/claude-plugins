// Array(3).fill(a 5-item literal).flat() holds 15 items
for (const x of Array(3).fill([1, 2, 3, 4, 5]).flat()) await agent("x" + x);
