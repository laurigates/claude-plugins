// a generator beside a loop over findings (#2670 review, from r8-verify)
await parallel([() => agent("a"), () => agent("b"), () => agent("c"),
  async () => { const g = function* () { while (true) yield 0 }; for (const _ of args.findings) await agent("v") },
]);
