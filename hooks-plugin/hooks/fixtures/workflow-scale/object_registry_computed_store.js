// a function stored under a const string key, called through reg.run: 12
const reg = {};
const k = "run";
reg[k] = () => agent("r");
for (let i = 0; i < 12; i++) await reg.run();
