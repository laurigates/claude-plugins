// a continue that skips the increment: the while is not counted, and its
// stated limit (4) is below ASSUMED, which is the true 8
let i = 0;
let n = 0;
while (i < 4) {
  await agent("x");
  n++;
  if (n % 2 === 1) continue;
  i++;
}
