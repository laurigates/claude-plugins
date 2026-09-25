// Map.forEach hands each value to its callback: 12 passes, 12 calls
const m = new Map([["a", () => agent("a")]]);
for (let i = 0; i < 12; i++) m.forEach((f) => f());
