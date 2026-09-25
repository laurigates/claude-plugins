// a closure the body calls decrements the counter: 20 passes, not 10
let i = 0;
const back = () => {
  i -= 1;
};
for (; i < 20; i += 2) {
  await agent("x" + i);
  back();
}
