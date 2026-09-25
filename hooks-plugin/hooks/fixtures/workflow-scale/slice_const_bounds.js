// slice bounds held in consts: 15 - 2 = 13
const a = 2, b = 15;
const xs = args.items.concat(args.items);
for (const x of xs.slice(a, b)) await agent(x);
