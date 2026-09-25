// a function stored by m.set(fn, value) is a key, reached through m.keys()
const m = new Map();
m.set(() => agent("a"), 1);
for (let i = 0; i < 20; i++) for (const k of m.keys()) k();
