// a key added to Object.prototype is one more key for every for...in
const o = { a: 1 };
Object.prototype.zz = 1;
for (let i = 0; i < 10; i++) for (const k in o) await agent(k);
delete Object.prototype.zz;
