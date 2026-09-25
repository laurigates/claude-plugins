// a class expression bound to a const, with a generator [Symbol.iterator]: 12
const Coll = class {
  *[Symbol.iterator]() {
    for (let i = 0; i < 12; i++) yield i;
  }
};
for (const x of new Coll()) await agent("x" + x);
