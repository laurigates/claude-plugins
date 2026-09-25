// the break counter starts below zero: -10 up to 2 is 12 passes, not the 3 its test states
let n = -10;
while (true) { await agent("x" + n); if (++n >= 2) break }
