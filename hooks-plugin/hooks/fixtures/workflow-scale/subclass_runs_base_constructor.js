// each instance of a subclass runs its base class's constructor: 20
class Base {
  constructor(i) {
    this.p = agent("w" + i);
  }
}
class Worker extends Base {}
for (let i = 0; i < 20; i++) await new Worker(i).p;
