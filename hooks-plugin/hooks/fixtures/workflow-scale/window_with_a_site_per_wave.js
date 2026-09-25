// a loop window with one more agent() per wave
const W = 3;
for (let i = 0; i < args.units.length; i += W) {
  await agent("plan");
  const wave = args.units.slice(i, i + W);
  await parallel(wave.map((c) => () => agent("w")));
}
