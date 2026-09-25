// a decrement under an `if` still moves the counter: its stated 20 is not divided
for (let i = 0; i < 20; i += 2) {
  await agent("x" + i);
  if (true) i -= 1;
}
