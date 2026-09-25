// a block function assigns to a var of its name in the enclosing scope (Annex B)
var spawn = null;
{
  function spawn(i) {
    return agent("x" + i);
  }
}
for (let i = 0; i < 12; i++) await spawn(i);
