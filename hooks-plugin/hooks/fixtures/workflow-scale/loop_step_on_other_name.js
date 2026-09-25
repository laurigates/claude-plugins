// the update steps a name the test does not compare, so it does not divide: 12
let k = 0;
for (let i = 12; i > 0; k += 4) {
  await agent("x" + i);
  i--;
}
