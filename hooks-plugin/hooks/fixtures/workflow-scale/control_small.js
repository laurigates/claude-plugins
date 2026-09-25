// control: two thunks, within the limit (#2670 review, from r8-verify)
await parallel([() => agent("a"), () => agent("b")]);
