// a pipeline a loop repeats inside an element (#2670 review, from r8-verify)
await parallel([() => agent("a"),
  async () => { for (const f of args.findings) await pipeline([1], (u) => agent("s")) },
]);
