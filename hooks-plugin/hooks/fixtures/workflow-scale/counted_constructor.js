// a class constructor a 12-pass loop runs with new
class K {
  constructor() {
    this.p = agent("x");
  }
}
for (let i = 0; i < 12; i++) new K();
