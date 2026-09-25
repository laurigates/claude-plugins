// .length counts UTF-16 code units: five emoji are 10
for (let i = 0; i < "🙂🙂🙂🙂🙂".length; i++) { await agent("a" + i); await agent("b" + i) }
