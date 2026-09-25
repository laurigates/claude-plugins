// a Set holds at most the items it was built from: 12
const topics = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"];
for (const t of new Set(topics)) await agent(t);
