// a loop around a .map over a trailing-comma literal (#2670 review, from r8-verify)
const D = [1, 2, 3,]
for (const f of args.findings) await parallel(D.map((d) => () => agent("a")));
