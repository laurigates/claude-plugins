// a 0.1 step reaches 0.9999999999999999 before 1 at runtime: 11 passes, not 10
for (let i = 0; i < 1; i += 0.1) await agent("x" + i);
