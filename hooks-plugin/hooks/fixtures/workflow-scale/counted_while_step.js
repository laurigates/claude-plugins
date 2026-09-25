// a counted while loop stepped by 2: 24 / 2 = 12 passes
let i = 0;
while (i < 24) {
  await agent("x" + i);
  i += 2;
}
