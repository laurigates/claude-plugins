// a local String is not the built-in: this one calls its argument 20 times
const String = (f) => { for (let i = 0; i < 20; i++) f() };
[() => agent("x")].map(String);
