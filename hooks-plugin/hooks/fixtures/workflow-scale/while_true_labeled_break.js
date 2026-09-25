// a labeled break from an inner loop leaves the while (true): its test states 20
let i = 0;
outer: while (true) {
  for (const u of [1]) {
    if (i >= 20) break outer;
    await agent("x" + i);
    i++;
  }
}
