// a class whose [Symbol.iterator] is a generator: 12 values per instance
class Coll {
  *[Symbol.iterator]() {
    for (let i = 0; i < 12; i++) yield i;
  }
}
for (const x of new Coll()) await agent("x" + x);
