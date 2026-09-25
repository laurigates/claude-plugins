// a method call may add keys through `this`: unbounded, never below 12 + 1
const cfg = {
  a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10, k: 11,
  add() {
    this.z = 1;
  },
};
cfg.add();
for (const k in cfg) await agent(k);
