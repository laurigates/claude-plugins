// a function taken out of an array by at() runs where it is called: 12 times
const fns = [() => agent("a")];
const run = fns.at(-1);
for (let i = 0; i < 12; i++) await run();
