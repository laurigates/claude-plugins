// Array.from over a 20-character string calls its mapper per character
await parallel(Array.from("abcdefghijklmnopqrst", (c) => () => agent(c)));
