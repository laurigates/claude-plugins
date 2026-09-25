// a fractional step: 6 / 0.5 = 12 passes, plus one for rounding
for (let i = 0; i < 6; i += 0.5) await agent("x" + i);
