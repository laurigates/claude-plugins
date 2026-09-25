// a function assigned to reg.run and called 20 times through reg.run()
const reg = {};
reg.run = () => agent("r");
for (let i = 0; i < 20; i++) await reg.run();
