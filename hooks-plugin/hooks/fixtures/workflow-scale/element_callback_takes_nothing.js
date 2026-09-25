// a callback with no parameters never sees an element, so none is called
[() => agent("a"), () => agent("b")].forEach(() => log("skip"));
