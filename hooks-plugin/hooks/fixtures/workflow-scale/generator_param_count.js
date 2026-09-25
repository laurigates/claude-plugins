// a generator's loop limit is a parameter the call passes 13
function* range(n) {
  for (let i = 0; i < n; i++) yield i;
}
for (const x of range(13)) await agent("x" + x);
