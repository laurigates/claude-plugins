// find hands the element it finds on; the caller runs it 12 times
const fns = [() => agent("a")];
const first = fns.find((f) => f.length === 0);
for (let i = 0; i < 12; i++) await first();
