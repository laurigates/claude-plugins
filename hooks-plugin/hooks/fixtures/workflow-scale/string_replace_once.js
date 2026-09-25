// replace with a string pattern, or a regex without /g, matches once
"aaaaaaaaaaaaaaaaaaaa".replace("a", () => {
  agent("r");
  return "b";
});
