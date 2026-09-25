// a /g regex matches at most once per UTF-16 position: 8 units, 9 positions
"🙂🙂🙂🙂".replace(/(?:)/g, () => { agent("a"); agent("b"); return "" });
