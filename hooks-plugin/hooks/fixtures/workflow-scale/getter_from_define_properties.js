// a getter Object.defineProperties names "run", read 12 times
const o = Object.defineProperties({}, {
  run: {
    get() {
      return agent("g");
    },
  },
});
for (let i = 0; i < 12; i++) await o.run;
