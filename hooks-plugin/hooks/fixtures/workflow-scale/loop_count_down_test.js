// a test that counts the counter down to zero: 12 passes
for (let i = 12; i--; ) await agent("x" + i);
