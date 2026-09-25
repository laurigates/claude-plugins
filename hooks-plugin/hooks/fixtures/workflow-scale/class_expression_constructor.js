// the constructor of a class expression bound to a const, built 20 times
const Worker = class {
  constructor(i) {
    this.p = agent("w" + i);
  }
};
for (let i = 0; i < 20; i++) await new Worker(i).p;
