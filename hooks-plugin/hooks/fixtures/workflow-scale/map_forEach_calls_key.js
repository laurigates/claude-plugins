// Map.forEach hands the key second: each key function is called once per unit
const m = new Map([[() => agent("a"), 1], [() => agent("b"), 2]]);
m.forEach((v, k) => { for (const u of units) k() });
