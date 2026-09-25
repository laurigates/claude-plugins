// this[K] with K a const string reads only that key
const reg = { a: () => agent("a"), b: () => agent("b"), run() { for (let i = 0; i < 20; i++) this[K]() } };
const K = "a";
reg.run();
