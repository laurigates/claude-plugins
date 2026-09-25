// an object whose [Symbol.iterator] is a generator yields 20 values
const it = {
  *[Symbol.iterator]() {
    for (let i = 0; i < 20; i++) yield i;
  },
};
for (const i of it) await agent("x" + i);
