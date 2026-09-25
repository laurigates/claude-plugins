// a window whose width is a parameter: a step with no number is taken as >= 1
async function waves(W) {
  for (let i = 0; i < args.units.length; i += W) {
    await parallel(args.units.slice(i, i + W).map((u) => () => agent(u)));
  }
}
await waves(3);
