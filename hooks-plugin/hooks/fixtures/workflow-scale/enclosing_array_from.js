// an Array.from mapper around the call (#2670 review, from r8-verify)
await Promise.all(Array.from({ length: 8 }, () => parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")])));
