// a const of the same name keeps the block function in its block (Annex B does not
// apply): only the call inside the block reaches it, the loop calls the const
const spawn = (i) => log(i);
{
  function spawn(i) {
    return agent("x" + i);
  }
  await spawn(0);
}
for (let i = 0; i < 12; i++) await spawn(i);
