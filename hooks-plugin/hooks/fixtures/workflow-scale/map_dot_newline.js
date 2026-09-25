// a newline between the dot and map (#2670 review, from r8-verify)
await parallel([() => args.xs.
  map((x) => agent("a")), () => agent("b")]);
