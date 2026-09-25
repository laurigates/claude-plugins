// entries() and values() iterate the list they are called on: 12 each
const topics = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"];
for (const [i, t] of topics.entries()) await agent(t + i);
for (const t of topics.values()) await agent(t);
