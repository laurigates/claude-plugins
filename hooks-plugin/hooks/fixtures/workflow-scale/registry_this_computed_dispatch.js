// a dispatch table: this[name]() may call any method, the one it is in included
const steps = { review() { return agent("r") }, fix() { return agent("f") }, run(name) { return this[name]() } };
for (const u of units) { steps.run("review"); steps.run("fix") }
