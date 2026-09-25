// a function the script defines, used as a template tag in a 12-pass loop
const review = (strings, ...vals) => agent(strings[0] + vals.join(""));
const files = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"];
for (const f of files) await review`check ${f}`;
