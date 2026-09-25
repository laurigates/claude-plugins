// a counter set before the loop is not reset by it: 10 passes
let i = 5;
i = 0;
while (i < 10) {
  await agent("x" + i);
  i++;
}
