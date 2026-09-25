// .call(...[this, a, b], fn): the spread holds the this and two arguments, fn lands third
function run(a, b, c) { for (let i = 0; i < 20; i++) c() }
run.call(...[null, 1, 2], () => agent("x"));
