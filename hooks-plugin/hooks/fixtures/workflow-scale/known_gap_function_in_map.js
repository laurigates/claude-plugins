// KNOWN GAP: a function stored in a Map, called by a 12-pass loop, costs ASSUMED (8)
const m = new Map([["k", (f) => agent("v")]]);
for (let i = 0; i < 12; i++) await m.get("k")(i);
