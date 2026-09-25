// an object with 8 keys and one more on Object.prototype: for...in visits 9
const o = { a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8 };
Object.prototype.zz = 1;
for (const k in o) await agent(k);
delete Object.prototype.zz;
