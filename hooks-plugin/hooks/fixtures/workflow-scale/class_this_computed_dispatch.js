// a class method reached through this[k]() is charged every call of it
class R { a() { return agent("a") } run(k) { for (let i = 0; i < 20; i++) this[k]() } }
new R().run("a");
