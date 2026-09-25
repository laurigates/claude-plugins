// the break comes after the work, so the pass that meets 12 still runs: 13
let n = 0;
while (true) {
  await agent("x" + n);
  if (n >= 12) break;
  n++;
}
