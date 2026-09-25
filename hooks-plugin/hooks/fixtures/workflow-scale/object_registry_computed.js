// a registry read by a computed key: reg[k] may be run, so each call charges it
const reg = { run: () => agent("r") };
const k = "run";
for (let i = 0; i < 20; i++) await reg[k]();
