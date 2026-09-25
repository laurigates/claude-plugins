// a rest list's forEach callback reaches its elements through the array parameter
const run = (...fns) =>
  fns.forEach((_, i, arr) => {
    for (const u of units) arr[i](u);
  });
run((u) => agent(u), (u) => agent(u));
