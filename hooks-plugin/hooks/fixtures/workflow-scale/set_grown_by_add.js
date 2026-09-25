// a Set grown by add() is costed like a pushed array: at least its source plus one
const seen = new Set(["a", "b"]);
seen.add("c");
for (const t of seen) await agent(t);
