// a newline-split .map fan-out over the limit (#2670 review, from r8-verify)
await parallel([
  () => args.xs.
    map((x) => agent("a")),
  () => args.xs.
    map((x) => agent("b")),
  () => args.xs.
    map((x) => agent("c")),
  () => args.xs.
    map((x) => agent("d")),
]);
