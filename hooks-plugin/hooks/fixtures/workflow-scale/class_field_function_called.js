// a function held in a class field, called 12 times through the field's name
class C {
  run = () => agent("c");
}
const c = new C();
for (let i = 0; i < 12; i++) await c.run();
