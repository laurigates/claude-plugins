// a tag's plain parameter takes the first substitution and its rest parameter the
// others: the first thunk runs 3 times, the second never
const tag = (strings, first, ...rest) => {
  for (let i = 0; i < 3; i++) first();
  return rest.length;
};
await tag`${() => agent("a")} ${() => agent("b")}`;
