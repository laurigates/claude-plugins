// a function stored by o.run = and reached through this[k]() with a computed key
const o = { all() { for (let i = 0; i < 20; i++) this[["r", "un"].join("")]() } };
o.run = () => agent("x");
o.all();
