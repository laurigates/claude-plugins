// a counter counting down to a negative constant: 0 down to -19 is 20 passes
const L = -20;
for (let i = 0; i > L; i--) await agent("x" + i);
