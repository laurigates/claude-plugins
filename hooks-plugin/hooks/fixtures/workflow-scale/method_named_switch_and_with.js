// object methods named switch and with, each called once per finding by a loop
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"),
  async () => {
    const o = { switch() { return agent("v") }, with() { return agent("w") } };
    for (const f of args.findings) {
      await o.switch();
      await o.with();
    }
  },
]);
