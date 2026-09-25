// the body resets the counter five times: 14 passes; the stated 20 is not divided
let k = 0;
for (let i = 0; i < 20; i += 2) {
  await agent("x" + i);
  if (k++ < 5) i = 0;
}
