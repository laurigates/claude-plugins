// a rest parameter's length is the most arguments a plain call passes it: 12, not ASSUMED
const each = (fn, ...items) => Promise.all(items.map((i) => fn(i)));
await each((x) => agent(x), "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l");
