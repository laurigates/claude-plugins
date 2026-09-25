// a counter starting at a negative const: -10 up to 2 is 12 passes
const start = -10;
for (let i = start; i < 2; i++) await agent("x" + i);
