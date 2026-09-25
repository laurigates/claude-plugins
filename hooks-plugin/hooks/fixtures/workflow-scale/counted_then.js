// a .then callback inside a 12-pass loop: 12 + 12
for (let i = 0; i < 12; i++) await agent("a").then(() => agent("b"));
