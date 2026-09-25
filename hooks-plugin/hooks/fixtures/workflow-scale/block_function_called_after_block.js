// a function declared in a block and called after it: sloppy code binds it in the
// enclosing scope (Annex B.3.3); round 9 found no caller and costed it at 0
{
  function spawn(i) {
    return agent("x" + i);
  }
}
for (let i = 0; i < 12; i++) await spawn(i);
