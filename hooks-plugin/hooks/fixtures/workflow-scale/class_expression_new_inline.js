// a class expression built in place, 12 times
for (let i = 0; i < 12; i++) new (class {
  constructor() {
    agent("c");
  }
})();
