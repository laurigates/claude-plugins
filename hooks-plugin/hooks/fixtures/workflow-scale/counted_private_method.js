// a private method another method calls, 12 times
class K {
  #go() { return agent("x") }
  run() { return this.#go() }
}
const k = new K();
for (let i = 0; i < 12; i++) await k.run();
