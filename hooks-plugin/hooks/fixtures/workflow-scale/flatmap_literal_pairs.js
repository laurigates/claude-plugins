// flatMap returning a 2-item literal per element: 6 x 2 = 12
const xs = ["a", "b", "c", "d", "e", "f"];
await parallel(xs.flatMap((t) => [t, t + "2"]).map((t) => () => agent(t)));
