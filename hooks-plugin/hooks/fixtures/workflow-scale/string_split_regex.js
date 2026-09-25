// a regex split adds its captured groups: at most (4 + 1) x (1 + 3) pieces
for (const p of "abcd".split(/()()()/)) await agent("x" + p);
