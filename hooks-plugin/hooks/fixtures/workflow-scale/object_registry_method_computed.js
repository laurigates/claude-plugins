// a registry method read by a computed key: 12
const reg = {
  run() {
    return agent("r");
  },
};
const k = "run";
for (let i = 0; i < 12; i++) await reg[k]();
