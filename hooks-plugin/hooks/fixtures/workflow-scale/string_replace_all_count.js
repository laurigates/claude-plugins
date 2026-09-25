// replaceAll with a literal pattern on a literal string: 13 occurrences
"a-a-a-a-a-a-a-a-a-a-a-a-a".replaceAll("a", () => {
  agent("r");
  return "b";
});
