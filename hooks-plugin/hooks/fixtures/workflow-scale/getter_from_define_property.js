// a getter Object.defineProperty names "run", read 20 times as o.run
const o = {};
Object.defineProperty(o, "run", {
  get() {
    return agent("g");
  },
});
for (let i = 0; i < 20; i++) await o.run;
