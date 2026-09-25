// a registry method calls another through `this`: 12
const reg = {
  run: () => agent("r"),
  all() {
    for (let i = 0; i < 12; i++) this.run();
  },
};
reg.all();
