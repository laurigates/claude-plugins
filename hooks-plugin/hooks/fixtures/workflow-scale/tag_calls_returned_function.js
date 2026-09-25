// a tag calls what a substitution returns; where that result goes is not followed,
// so the inner thunk is costed at ASSUMED per call, not 0
const call2 = (strings, make) => make()();
for (let i = 0; i < 12; i++) await call2`${() => () => agent("t" + i)}`;
