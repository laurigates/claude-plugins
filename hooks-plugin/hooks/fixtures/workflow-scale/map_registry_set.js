// a function stored by m.set and called through m.get: 12
const m = new Map();
m.set("a", () => agent("a"));
for (let i = 0; i < 12; i++) await m.get("a")();
