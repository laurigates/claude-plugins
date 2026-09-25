// a downward loop stepped by `j = j - 20`: 240 / 20 = 12 passes
for (let j = 240; j > 0; j = j - 20) await agent("x" + j);
