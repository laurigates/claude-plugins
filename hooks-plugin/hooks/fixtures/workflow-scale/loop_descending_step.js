// a downward loop with a literal step: 100 / 10 = 10 passes, at the limit, silent
for (let i = 100; i > 0; i -= 10) await agent("x" + i);
