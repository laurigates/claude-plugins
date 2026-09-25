// a loop window over a 20-item list: 20, not 20 x 3
const L = Array.from({ length: 20 }, (_, i) => i);
const W = 3;
for (let i = 0; i < L.length; i += W) {
  const wave = L.slice(i, i + W);
  await parallel(wave.map((c) => () => agent("w")));
}
