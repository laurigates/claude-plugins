// a pattern that matches the empty string matches at every position, the end
// included: 20 characters, 21 matches
"aaaaaaaaaaaaaaaaaaaa".replace(/x*/g, () => {
  agent("r");
  return "";
});
