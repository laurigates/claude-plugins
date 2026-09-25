// a rest-parameter helper also passed on as a value: not every caller is visible,
// so its list is costed at ASSUMED, not at the 2 its plain call passes
const each = (fn, ...items) => Promise.all(items.map((i) => fn(i)));
await each((x) => agent(x), "a", "b");
const later = [each];
await later[0]((x) => agent(x), "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l");
