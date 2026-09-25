// for...in over a string visits every UTF-16 index
for (const k in "🙂🙂🙂🙂🙂") { await agent("a" + k); await agent("b" + k) }
