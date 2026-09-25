// a template tag called through a const alias: 12
const tag = (s, f) => {
  for (let i = 0; i < 12; i++) f();
};
const t2 = tag;
t2`${() => agent("t")}`;
