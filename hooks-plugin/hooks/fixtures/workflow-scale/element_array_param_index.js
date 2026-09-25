// an inline array's forEach callback calls elements through its third parameter,
// the array itself; any element may be reached, so each is charged every call
[() => agent("a"), () => agent("b")].forEach((_, i, arr) => {
  for (const u of units) arr[i](u);
});
