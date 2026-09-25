// the body undoes half of each step (`i--` against `i += 2`): 20 passes, not 10
for (let i = 0; i < 20; i += 2) {
  await agent("x" + i);
  i--;
}
