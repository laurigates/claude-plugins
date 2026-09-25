// a counted while from a negative start: -10 up to 2 is 12 passes
let i = -10;
while (i < 2) {
  await agent("x" + i);
  i++;
}
