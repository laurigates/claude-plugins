// destructuring reads the getter: 20 passes, 20 agents
const o = {
  get run() {
    return agent("g");
  },
};
for (let i = 0; i < 20; i++) {
  const { run } = o;
  await run;
}
