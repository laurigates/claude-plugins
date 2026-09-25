// a registry function destructured into a name, called 12 times
const reg = { a: () => agent("a") };
const { a } = reg;
for (let i = 0; i < 12; i++) await a();
