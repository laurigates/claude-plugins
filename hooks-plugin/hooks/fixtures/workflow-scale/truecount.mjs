// Run a workflow-shaped fixture with a counting agent() and print how many
// agents it created: the ground truth test-workflow-scale-guard.sh compares
// workflow-scale-estimate.py against.
//
// Every runtime list (`args.<anything>`, `units`, `items`, ...) holds 8 items,
// the width the estimator assumes for a list it cannot bound, so a fixture's
// true count and its estimate are measured on the same convention. `parallel`
// calls each thunk once and `pipeline` runs every stage once per item, as the
// Workflow runtime does. A fixture that throws, or reads a name not provided
// here, prints `ERR <message>` and exits 1: its true count is unknown.
//
// Usage: node truecount.mjs <fixture.js>
import { readFileSync } from "node:fs";

const eight = () => ["i1", "i2", "i3", "i4", "i5", "i6", "i7", "i8"];
const identity = (v) => v;
const CAP = 100000;
let count = 0;

const env = Object.create(null);
Object.assign(env, {
  agent: async () => {
    count += 1;
    if (count > CAP) throw new Error(`more than ${CAP} agents`);
    return { findings: eight(), verdict: "ok" };
  },
  parallel: async (thunks) => Promise.all(thunks.map((t) => (typeof t === "function" ? t() : t))),
  pipeline: async (items, ...stages) => {
    const out = [];
    for (const item of items) {
      let value = item;
      for (const stage of stages) value = await stage(value, item);
      out.push(value);
    }
    return out;
  },
  args: new Proxy({}, { get: () => eight() }),
  log: () => {},
  phase: () => {},
  ok: () => true,
  trim: identity,
  f: identity,
  g: identity,
  h: identity,
  b: identity,
  s: "x",
  a: 1,
  c: 1,
  x: 1,
  extra: 1,
});
for (const name of ["units", "items", "xs", "ys", "gaps", "changedFiles", "ITEMS"]) env[name] = eight();

// `export` is not valid inside a function body; the declarations it prefixes
// are. The `;` keeps the statement boundary `export` implied, so a line that
// now starts with `/` still opens a regex rather than dividing the line above.
const src = readFileSync(process.argv[2], "utf8").replace(/^export (default )?/gm, ";");
const AsyncFunction = (async () => {}).constructor;
try {
  // Sloppy-mode `with` puts the stubs in scope beneath the fixture's own
  // declarations, so a fixture may declare a name the harness also provides.
  await new AsyncFunction("__env", `with (__env) {\n${src}\n}`)(env);
} catch (err) {
  console.log(`ERR ${String(err && err.message).split("\n")[0]}`);
  process.exit(1);
}
console.log(count);
