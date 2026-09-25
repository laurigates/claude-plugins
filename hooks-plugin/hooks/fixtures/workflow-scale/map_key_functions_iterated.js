// functions stored as a Map's keys: `m.keys()` hands each on, called once per unit
const m = new Map([[() => agent("a"), "a"], [() => agent("b"), "b"]]);
for (const u of units) for (const k of m.keys()) await k();
