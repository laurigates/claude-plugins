// yield* of a 3-item literal and of a runtime list (ASSUMED 8): 11
function* g() {
  yield* [1, 2, 3];
  yield* units;
}
for (const x of g()) await agent("x" + x);
