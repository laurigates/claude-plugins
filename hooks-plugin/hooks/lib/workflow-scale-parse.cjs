// Parse a Workflow script from stdin and print its ESTree AST as JSON.
//
// workflow-scale-estimate.py runs this with `node` and walks the tree. The
// parser is acorn 8.18.0, vendored unmodified from the npm tarball
// (https://registry.npmjs.org/acorn/-/acorn-8.18.0.tgz, integrity
// sha512-lGq+9yr1/GuAWaVYIHRjvvySG5/4VfKIvC8EWxStPdcDh/Ka7FG3twP6v4d5BkravUilhIAsG4Qj83t02LWUPQ==),
// MIT licensed; see vendor/acorn/LICENSE.
//
// A script acorn rejects prints {"error": "..."} and exits 0, so the caller can
// tell a syntax error (ask) from a missing or crashing parser (fall back).
"use strict";

const fs = require("fs");
const path = require("path");
const acorn = require(path.join(__dirname, "vendor", "acorn", "acorn.js"));

const src = fs.readFileSync(0, "utf8");
let ast;
try {
  // A Workflow script is a module with top-level `await` and, in the shipped
  // templates, a top-level `return`.
  ast = acorn.parse(src, {
    ecmaVersion: "latest",
    sourceType: "module",
    allowReturnOutsideFunction: true,
    allowAwaitOutsideFunction: true,
    allowHashBang: true,
    locations: true,
  });
} catch (err) {
  process.stdout.write(JSON.stringify({ error: String(err && err.message) }));
  process.exit(0);
}
// BigInt and RegExp literal values do not serialise; the estimator reads neither.
process.stdout.write(
  JSON.stringify(ast, (key, value) => {
    if (typeof value === "bigint") return value.toString();
    if (value instanceof RegExp) return null;
    return value;
  }),
);
