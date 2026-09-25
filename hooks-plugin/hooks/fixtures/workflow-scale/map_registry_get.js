// a function stored in a Map and called through m.get() by a 12-pass loop: 12
// (a pinned known gap until round 11, costed at ASSUMED)
const m = new Map([["k", (f) => agent("v")]]);
for (let i = 0; i < 12; i++) await m.get("k")(i);
