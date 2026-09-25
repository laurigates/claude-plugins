// a while (true) left by a break whose test states 20
let i = 0;
while (true) {
  if (i >= 20) break;
  await agent("x" + i);
  i++;
}
