// a do...while loop around the call (#2670 review, from r8-verify)
let k = 0; do { await parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")]); k++ } while (k < 8);
