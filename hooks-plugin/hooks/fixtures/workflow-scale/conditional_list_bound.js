// a list chosen by a condition is bounded by the longer branch
const flag = ok();
const xs = flag ? ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"] : ["a", "b"];
for (const x of xs) await agent(x);
