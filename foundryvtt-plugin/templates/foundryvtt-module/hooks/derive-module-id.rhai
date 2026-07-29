// Derive the Foundry module id from the repo name: foundryvtt-x -> x.
//
// The id becomes module.json `id`, the Foundry install folder, and the release
// zip name — all three must byte-match, so it is derived from one source rather
// than prompted for separately. Mirrors scaffold.py's `--id` default.

let name = variable::get("project-name");
let module_id = name;

if name.starts_with("foundryvtt-") {
    module_id = name.sub_string(11);
} else {
    print("warning: repo name '" + name + "' does not start with 'foundryvtt-' (the workspace convention)");
}

if module_id == "" {
    abort("module id is empty — pass a repo name like 'foundryvtt-initiative-tweaks'");
}

// Lowercase kebab-case only: letters, digits, single interior hyphens.
let allowed = "abcdefghijklmnopqrstuvwxyz0123456789-";
let previous_was_hyphen = false;

for i in 0..module_id.len {
    let ch = module_id[i];
    if !allowed.contains(ch) {
        abort("module id '" + module_id + "' must be lowercase kebab-case (letters, digits, single hyphens) — it becomes the install folder, the zip name, and the module.json id");
    }
    let is_hyphen = ch == '-';
    if is_hyphen && (i == 0 || i == module_id.len - 1 || previous_was_hyphen) {
        abort("module id '" + module_id + "' must not start, end, or double up on hyphens");
    }
    previous_was_hyphen = is_hyphen;
}

variable::set("module_id", module_id);

// Date-derived values. Prompting for these would invite a stale copyright year
// or a hand-typed ADR date that disagrees with the commit that adds it.
// `variable::set` takes strings only — passing the i64 from `system::date()`
// directly fails with "Function not found: variable::set (…, i64)".
let now = system::date();
variable::set("copyright_year", "" + now.year);

let month = if now.month < 10 { "0" + now.month } else { "" + now.month };
let day = if now.day < 10 { "0" + now.day } else { "" + now.day };
variable::set("today", "" + now.year + "-" + month + "-" + day);
