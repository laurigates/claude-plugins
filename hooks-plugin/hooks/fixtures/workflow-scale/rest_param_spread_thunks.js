// thunks spread into a rest parameter, the second spread after the first: once each
const all = (...ts) => Promise.all(ts.map((t) => t()));
const files = ["a", "b", "c", "d", "e", "f", "g", "h"];
await all(...files.map((f) => () => agent(f)), ...files.map((f) => () => agent(f + "2")));
