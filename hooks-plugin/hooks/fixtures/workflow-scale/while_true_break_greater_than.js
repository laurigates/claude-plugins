// a > break is met one pass later than a >= one: n runs 0 to 12, 13 agents
let n = 0
while (true) { await agent("x" + n); if (n > 11) break; n++ }
