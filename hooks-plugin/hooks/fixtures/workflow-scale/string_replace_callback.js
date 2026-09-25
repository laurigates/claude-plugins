// a global regex replace calls its function once per match; a 20-character
// string matches at most 21 times
"aaaaaaaaaaaaaaaaaaaa".replace(/a/g, () => {
  agent("r");
  return "b";
});
