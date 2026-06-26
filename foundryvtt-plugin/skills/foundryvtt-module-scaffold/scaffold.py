#!/usr/bin/env python3
"""Scaffold a new FoundryVTT module repo (TypeScript + Vite build, bun, biome).

Generates a CI-green, ready-to-implement FoundryVTT v13 module: a real
`module.json` manifest (GitHub-release distribution), a Vite library build
(`src/module.ts` -> `dist/<id>.mjs`), strict TypeScript with local Foundry
ambient shims, biome lint/format, a Vitest smoke suite, CI + release-please
workflows (release-please bumps both `package.json` and `module.json` $.version
and the release job zips `dist/` and attaches it to the GitHub release),
localization, scoped CSS, a justfile, README, CLAUDE.md, and an ADR recording
the toolchain decision.

Three variants:
  - basic      settings + init/ready hooks + i18n + scoped CSS (the default)
  - app        basic + an ApplicationV2/HandlebarsApplicationMixin window and a
               settings-menu button that opens it (Foundry v13 UI)
  - libwrapper basic + a libWrapper-guarded patch of a core method with a manual
               monkey-patch fallback when lib-wrapper is not active

Distribution is by GitHub release manifest URL: `manifest` points at
`releases/latest/download/module.json` and `download` at
`releases/latest/download/<id>.zip`. No foundryvtt.com submission is needed to
install-by-URL; that is only required to be LISTED in the in-app package browser.

Stdlib only. Run with `python3 scaffold.py` or `uv run scaffold.py`.

Examples
--------
Basic settings+hooks module:
    python3 scaffold.py \
        --name foundryvtt-initiative-tweaks \
        --display "Initiative Tweaks" \
        --desc "Small quality-of-life tweaks to the combat initiative tracker."

Module with an ApplicationV2 UI panel:
    python3 scaffold.py \
        --name foundryvtt-party-overview \
        --display "Party Overview" \
        --desc "A dockable party status panel for GMs." \
        --variant app

Module that patches a core method via libWrapper:
    python3 scaffold.py \
        --name foundryvtt-token-vision-tweak \
        --display "Token Vision Tweak" \
        --desc "Adjusts token vision drawing via a libWrapper-guarded patch." \
        --variant libwrapper
"""

from __future__ import annotations

import argparse
import datetime
import re
import sys
from pathlib import Path

AUTHOR_DEFAULT = "Lauri Gates"
PUBLISHER_DEFAULT = "laurigates"

# Pinned tool versions — kept in ONE place so a pin can never drift between
# biome.json, the CI setup-biome step, and the justfile.
BIOME_VERSION = "2.4.15"
TYPESCRIPT_VERSION = "^5.7.0"
VITE_VERSION = "^6.0.0"
VITE_STATIC_COPY_VERSION = "^2.2.0"
VITEST_VERSION = "^3.0.0"

# FoundryVTT compatibility defaults. `verified` tracks the version the local
# harness pins; `minimum` is intentionally a little broader. Override per-module
# with --fvtt-min / --fvtt-verified.
FVTT_MIN_DEFAULT = "12"
FVTT_VERIFIED_DEFAULT = "13"

VALID_VARIANTS = ("basic", "app", "libwrapper")


# --------------------------------------------------------------------------- #
# Name derivation
# --------------------------------------------------------------------------- #
def derive(name: str, module_id: str | None) -> dict[str, str]:
    """Derive the family of names a module needs from its repo name + id.

    The repo name (``--name``) is the GitHub repo (e.g.
    ``foundryvtt-initiative-tweaks``); the module id (``--id``, defaulting to the
    repo name with a leading ``foundryvtt-`` stripped) is the canonical Foundry
    identifier that must match the install folder, the zip, and ``module.json``.
    """
    if not name.startswith("foundryvtt-"):
        print(
            f"warning: repo name '{name}' does not start with 'foundryvtt-' "
            "(the workspace convention)",
            file=sys.stderr,
        )
    mid = module_id or name.removeprefix("foundryvtt-")
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", mid):
        print(
            f"error: module id '{mid}' must be lowercase kebab-case "
            "(letters, digits, single hyphens) — it becomes the install folder, "
            "the zip name, and the module.json id",
            file=sys.stderr,
        )
        raise SystemExit(2)
    return {
        "NAME": name,  # foundryvtt-initiative-tweaks (GitHub repo)
        "MODULE_ID": mid,  # initiative-tweaks (Foundry id / folder / zip)
        "MODULE_CLASS": _pascal(mid),  # InitiativeTweaks (TS class prefix)
    }


def _pascal(mid: str) -> str:
    """initiative-tweaks -> InitiativeTweaks."""
    return "".join(part[:1].upper() + part[1:] for part in mid.split("-"))


# --------------------------------------------------------------------------- #
# Template substitution — @@TOKEN@@ placeholders (avoids brace conflicts with
# JSON / JS / TS literal braces).
# --------------------------------------------------------------------------- #
def subst(text: str, ctx: dict[str, str]) -> str:
    for key, val in ctx.items():
        text = text.replace(f"@@{key}@@", val)
    return text


# --------------------------------------------------------------------------- #
# Config / metadata templates
# --------------------------------------------------------------------------- #
MODULE_JSON = """\
{
  "id": "@@MODULE_ID@@",
  "title": "@@DISPLAY@@",
  "description": "@@DESC@@",
  "version": "0.1.0",
  "compatibility": {
    "minimum": "@@FVTT_MIN@@",
    "verified": "@@FVTT_VERIFIED@@"
  },
  "authors": [
    {
      "name": "@@AUTHOR@@"
    }
  ],
  "esmodules": ["@@MODULE_ID@@.mjs"],
  "styles": ["styles/@@MODULE_ID@@.css"],
  "languages": [
    {
      "lang": "en",
      "name": "English",
      "path": "lang/en.json"
    }
  ],
  "url": "https://github.com/@@PUBLISHER@@/@@NAME@@",
  "manifest": "https://github.com/@@PUBLISHER@@/@@NAME@@/releases/latest/download/module.json",
  "download": "https://github.com/@@PUBLISHER@@/@@NAME@@/releases/latest/download/@@MODULE_ID@@.zip",
  "readme": "https://github.com/@@PUBLISHER@@/@@NAME@@/blob/main/README.md",
  "changelog": "https://github.com/@@PUBLISHER@@/@@NAME@@/blob/main/CHANGELOG.md",
  "bugs": "https://github.com/@@PUBLISHER@@/@@NAME@@/issues",
  @@RELATIONSHIPS@@"flags": {
    "hotReload": {
      "extensions": ["css", "hbs", "json"],
      "paths": ["styles", "templates", "lang"]
    }
  }
}
"""

RELATIONSHIPS_LIBWRAPPER = """\
"relationships": {
    "recommends": [
      {
        "id": "lib-wrapper",
        "type": "module",
        "reason": "Reduces conflicts when patching core methods.",
        "manifest": "https://github.com/ruipin/fvtt-lib-wrapper/releases/latest/download/module.json",
        "compatibility": { "minimum": "1.0.0.0" }
      }
    ]
  },
  """

PACKAGE_JSON = """\
{
  "name": "@@NAME@@",
  "version": "0.1.0",
  "description": "@@DESC@@",
  "type": "module",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "typecheck": "tsc --noEmit",
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "format": "biome format --write .",
    "test": "vitest run",
    "test:watch": "vitest",
    "check": "bun run typecheck && bun run build && bun run lint && bun run test"
  },
  "keywords": [
    "foundryvtt",
    "foundry-vtt",
    "module"
  ],
  "author": "@@AUTHOR@@",
  "license": "MIT",
  "devDependencies": {
    "@biomejs/biome": "@@BIOME_VERSION@@",
    "typescript": "@@TYPESCRIPT_VERSION@@",
    "vite": "@@VITE_VERSION@@",
    "vite-plugin-static-copy": "@@VITE_STATIC_COPY_VERSION@@",
    "vitest": "@@VITEST_VERSION@@"
  }
}
"""

VITE_CONFIG = """\
import { defineConfig } from 'vite';
import { viteStaticCopy } from 'vite-plugin-static-copy';

const MODULE_ID = '@@MODULE_ID@@';

// Vite library build: a single ESM bundle at dist/<id>.mjs (the path
// module.json's `esmodules` references), plus static-copied manifest + assets.
// Foundry serves dist/ as the module root, so output paths must byte-match the
// manifest. The dev server proxies everything to Foundry on :30000 except this
// module's own files, which Vite serves with HMR.
export default defineConfig(({ mode }) => ({
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    sourcemap: mode === 'development',
    minify: false,
    target: 'es2022',
    lib: {
      entry: 'src/module.ts',
      formats: ['es'],
      fileName: () => `${MODULE_ID}.mjs`,
    },
  },
  plugins: [
    viteStaticCopy({
      targets: [
        { src: 'module.json', dest: '.' },
        { src: 'lang', dest: '.' },
        { src: 'styles', dest: '.' },@@STATIC_COPY_TEMPLATES@@
      ],
    }),
  ],
  server: {
    port: 30001,
    proxy: {
      [`^(?!/modules/${MODULE_ID}/)`]: 'http://localhost:30000/',
      '/socket.io': { target: 'ws://localhost:30000', ws: true },
    },
  },
}));
"""

STATIC_COPY_TEMPLATES = "\n        { src: 'templates', dest: '.' },"

TSCONFIG = """\
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "noEmit": true,
    "allowJs": true,
    "checkJs": false,
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "skipLibCheck": true,
    "types": []
  },
  "include": ["src"]
}
"""

BIOME_JSON = """\
{
  "$schema": "https://biomejs.dev/schemas/@@BIOME_VERSION@@/schema.json",
  "vcs": { "enabled": true, "clientKind": "git", "useIgnoreFile": true },
  "files": { "includes": ["**"] },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100,
    "lineEnding": "lf"
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "suspicious": {
        "noExplicitAny": "off",
        "noConsole": "off"
      },
      "complexity": {
        "noThisInStatic": "off"
      }
    }
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "single",
      "semicolons": "always",
      "trailingCommas": "all",
      "arrowParentheses": "always"
    }
  },
  "assist": { "enabled": true, "actions": { "source": { "organizeImports": "off" } } }
}
"""

VITEST_CONFIG = """\
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    setupFiles: ['tests/setup.ts'],
  },
});
"""

GITIGNORE = """\
node_modules/
dist/
coverage/
*.log

# Editor
.vscode/
.idea/
*.swp

# OS
.DS_Store
Thumbs.db

# Local notes / scratch
TODO.local.md
NOTES.local.md
"""

GITATTRIBUTES = """\
* text=auto eol=lf
*.png binary
*.jpg binary
*.webp binary
bun.lock linguist-generated=true
"""

RP_CONFIG = """\
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "node",
      "package-name": "@@NAME@@",
      "changelog-path": "CHANGELOG.md",
      "bump-minor-pre-major": true,
      "bump-patch-for-minor-pre-major": true,
      "extra-files": [
        {
          "type": "json",
          "path": "module.json",
          "jsonpath": "$.version"
        }
      ]
    }
  },
  "pull-request-title-pattern": "chore: release ${version}",
  "changelog-sections": [
    { "type": "feat", "section": "Features" },
    { "type": "fix", "section": "Bug Fixes" },
    { "type": "perf", "section": "Performance Improvements" },
    { "type": "docs", "section": "Documentation" },
    { "type": "chore", "section": "Miscellaneous", "hidden": false }
  ],
  "separate-pull-requests": false
}
"""

RP_MANIFEST = """\
{
  ".": "0.1.0"
}
"""

CI_YML = """\
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  lint:
    name: Lint & format (biome)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Biome
        uses: biomejs/setup-biome@v2
        with:
          # Pin to the schema version declared in biome.json. Bump in lockstep
          # via `biome migrate` when upgrading.
          version: @@BIOME_VERSION@@
      - name: Biome check
        run: biome check .

  typecheck-build:
    name: Typecheck & build (Vite)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Bun
        uses: oven-sh/setup-bun@v2
      - name: Install dependencies
        run: bun install --frozen-lockfile
      - name: Typecheck
        run: bun run typecheck
      - name: Build
        run: bun run build

  test:
    name: Tests (Vitest)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Bun
        uses: oven-sh/setup-bun@v2
      - name: Install dependencies
        run: bun install --frozen-lockfile
      - name: Run Vitest
        run: bun run test

  security:
    name: Security scanning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          # gitleaks scans <prev>^..<head>; the parent commit must be present.
          fetch-depth: 0
      - name: Gitleaks secret scan
        uses: gitleaks/gitleaks-action@v3
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
"""

RELEASE_PLEASE_YML = """\
name: "Release: release-please"

on:
  push:
    branches:
      - main
  workflow_dispatch: {}

concurrency:
  group: release-please-${{ github.repository }}
  cancel-in-progress: false

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - name: Generate GitHub App Token
        id: app-token
        uses: actions/create-github-app-token@v3
        with:
          app-id: ${{ vars.RELEASE_PLEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_PLEASE_PRIVATE_KEY }}
      - uses: googleapis/release-please-action@v4
        id: release
        with:
          token: ${{ steps.app-token.outputs.token }}

      # When a release is cut, build the module, zip dist/, and attach the
      # FoundryVTT install assets to the GitHub release. The manifest URL
      # (releases/latest/download/module.json) and download URL
      # (releases/latest/download/@@MODULE_ID@@.zip) resolve to these assets.
      - name: Checkout
        if: ${{ steps.release.outputs.release_created }}
        uses: actions/checkout@v4
      - name: Set up Bun
        if: ${{ steps.release.outputs.release_created }}
        uses: oven-sh/setup-bun@v2
      - name: Install dependencies
        if: ${{ steps.release.outputs.release_created }}
        run: bun install --frozen-lockfile
      - name: Build module
        if: ${{ steps.release.outputs.release_created }}
        run: bun run build
      - name: Package module zip
        if: ${{ steps.release.outputs.release_created }}
        run: |
          cd dist
          zip -r ../@@MODULE_ID@@.zip .
      - name: Upload release assets
        if: ${{ steps.release.outputs.release_created }}
        env:
          GITHUB_TOKEN: ${{ steps.app-token.outputs.token }}
        run: |
          gh release upload "${{ steps.release.outputs.tag_name }}" \\
            @@MODULE_ID@@.zip dist/module.json --clobber
"""

RENOVATE_JSON = """\
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"]
}
"""

RENOVATE_YML = """\
name: Renovate

on:
  schedule:
    - cron: '23 */4 * * *'
  workflow_dispatch:
    inputs:
      dryRun:
        description: 'Dry run mode'
        required: false
        default: 'false'
        type: choice
        options:
          - 'false'
          - 'full'
          - 'lookup'

permissions:
  contents: write
  pull-requests: write
  issues: write
  packages: read

jobs:
  renovate:
    uses: laurigates/.github/.github/workflows/reusable-renovate.yml@main
    with:
      dry-run: ${{ inputs.dryRun || 'false' }}
"""

JUSTFILE = """\
# @@NAME@@ — task runner. Run `just` (or `just --list`) for recipes.

# Show available recipes.
default:
    @just --list

# Run the Vite dev server (proxies to Foundry on :30000 with HMR).
dev:
    bun run dev

# Build the ESM bundle + static assets to dist/.
build:
    bun run build

# Typecheck the TypeScript source (tsc --noEmit).
typecheck:
    bun run typecheck

# Lint TS/JSON with biome (no changes).
lint:
    bun run lint

# Auto-format + auto-fix with biome.
format:
    bun run lint:fix

# Run the Vitest suite.
test:
    bun run test

# Typecheck + build + lint + test — the local CI gate.
check: typecheck build lint test
"""

LICENSE = """\
MIT License

Copyright (c) @@YEAR@@ @@AUTHOR@@

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


# --------------------------------------------------------------------------- #
# Source templates
# --------------------------------------------------------------------------- #
FOUNDRY_SHIMS = """\
// Ambient declarations for the FoundryVTT client globals this module uses.
//
// These keep `tsc` green and self-contained without depending on the (beta,
// git-only) `fvtt-types` package. They are intentionally loose: their job is to
// type *our* call sites, not to model the whole Foundry API. ALWAYS verify the
// real API against https://foundryvtt.com/api/ or the live console before
// relying on a shape — do not treat these declarations as authoritative.
//
// To opt into the full community types instead, add
//   fvtt-types: "github:League-of-Foundry-Developers/foundry-vtt-types#main"
// as a devDependency, set tsconfig `compilerOptions.types` to ["fvtt-types"],
// and delete this file.

export {};

declare global {
  const game: any;
  const ui: any;
  const canvas: any;
  const CONFIG: any;
  const CONST: any;
  const foundry: any;
  const Token: any;
  const libWrapper: any;

  const Hooks: {
    on(hook: string, fn: (...args: any[]) => unknown): number;
    once(hook: string, fn: (...args: any[]) => unknown): number;
    off(hook: string, id: number): void;
    call(hook: string, ...args: any[]): boolean;
    callAll(hook: string, ...args: any[]): boolean;
  };
}
"""

CONSTANTS_TS = """\
/** The Foundry module id — must match module.json `id`, the install folder, and
 * the release zip name. Derived from a single source so it can never drift. */
export const MODULE_ID = '@@MODULE_ID@@';

/** Human-readable title, used as a console log prefix. */
export const MODULE_TITLE = '@@DISPLAY@@';
"""

MODULE_TS = """\
import { MODULE_ID, MODULE_TITLE } from './constants';
import { registerSettings } from './settings';@@MODULE_IMPORTS@@

/** Namespaced console logger so module messages are easy to filter. */
function log(...args: unknown[]): void {
  console.log(`${MODULE_TITLE} |`, ...args);
}

// `init` — register settings and wrap methods. `game` data is NOT populated yet.
Hooks.once('init', () => {
  log(`Initializing ${MODULE_ID}`);
  registerSettings();@@INIT_BODY_EXTRA@@
});

// `ready` — the world and `game.*` are fully populated.
Hooks.once('ready', () => {
  log('Ready');@@READY_BODY_EXTRA@@
});
"""

SETTINGS_TS = """\
import { MODULE_ID } from './constants';@@SETTINGS_IMPORTS@@

/** Register this module's settings. Called from the `init` hook. The `name` and
 * `hint` values are i18n keys (resolved at render time), not literal strings. */
export function registerSettings(): void {
  game.settings.register(MODULE_ID, 'enabled', {
    name: `${MODULE_ID}.Settings.Enabled.Name`,
    hint: `${MODULE_ID}.Settings.Enabled.Hint`,
    scope: 'world',
    config: true,
    type: Boolean,
    default: true,
    requiresReload: false,
  });
@@SETTINGS_MENU@@}

/** Read a boolean module setting. */
export function getSetting(key: string): unknown {
  return game.settings.get(MODULE_ID, key);
}
"""

SETTINGS_MENU_APP = """\
  game.settings.registerMenu(MODULE_ID, 'openApp', {
    name: `${MODULE_ID}.Menu.Name`,
    label: `${MODULE_ID}.Menu.Label`,
    hint: `${MODULE_ID}.Menu.Hint`,
    icon: 'fa-solid fa-table-list',
    type: @@MODULE_CLASS@@App,
    restricted: false,
  });
"""

APP_TS = """\
import { MODULE_ID, MODULE_TITLE } from './constants';

const { ApplicationV2, HandlebarsApplicationMixin } = foundry.applications.api;

/**
 * A minimal Foundry v13 ApplicationV2 window using HandlebarsApplicationMixin.
 * Templates listed in `static PARTS` are auto-loaded by the mixin on render.
 * Open it with `new @@MODULE_CLASS@@App().render(true)`.
 */
export class @@MODULE_CLASS@@App extends HandlebarsApplicationMixin(ApplicationV2) {
  static DEFAULT_OPTIONS = {
    id: `${MODULE_ID}-app`,
    tag: 'div',
    classes: [MODULE_ID, `${MODULE_ID}-app`],
    window: {
      title: `${MODULE_ID}.App.Title`,
      icon: 'fa-solid fa-table-list',
      resizable: true,
    },
    position: { width: 480, height: 'auto' },
    actions: {
      refresh: @@MODULE_CLASS@@App.#onRefresh,
    },
  };

  static PARTS = {
    main: { template: `modules/${MODULE_ID}/templates/app.hbs` },
  };

  /** Build the render context the Handlebars template sees. */
  async _prepareContext(options: Record<string, unknown>): Promise<Record<string, unknown>> {
    const context = await super._prepareContext(options);
    return foundry.utils.mergeObject(context, {
      moduleTitle: MODULE_TITLE,
      isGM: game.user?.isGM ?? false,
    });
  }

  // Declared `static`, but the framework rebinds `this` to the live instance.
  static async #onRefresh(
    this: @@MODULE_CLASS@@App,
    _event: Event,
    _target: HTMLElement,
  ): Promise<void> {
    await this.render();
  }
}
"""

APP_HBS = """\
<section class="@@MODULE_ID@@-app-body">
  <h2>{{moduleTitle}}</h2>
  <p>{{localize "@@MODULE_ID@@.App.Body"}}</p>
  {{#if isGM}}
  <p class="@@MODULE_ID@@-gm-note">{{localize "@@MODULE_ID@@.App.GMNote"}}</p>
  {{/if}}
  <footer class="@@MODULE_ID@@-app-footer">
    <button type="button" data-action="refresh">
      <i class="fa-solid fa-rotate"></i> {{localize "@@MODULE_ID@@.App.Refresh"}}
    </button>
  </footer>
</section>
"""

PATCHES_TS = """\
import { MODULE_ID, MODULE_TITLE } from './constants';

/**
 * Register method patches. Uses libWrapper when the lib-wrapper module is
 * active (the conflict-safe path) and falls back to a manual monkey-patch with
 * the same wrapper contract when it is not. Called from the `init` hook.
 *
 * The target below is illustrative — replace `Token.prototype._draw` and the
 * wrapper body with the core/system method you actually need to patch. Verify
 * the method exists at the targeted Foundry version before relying on it:
 * https://foundryvtt.com/api/ and https://github.com/ruipin/fvtt-lib-wrapper
 */
export function registerPatches(): void {
  const target = 'Token.prototype._draw';

  // A WRAPPER must always continue the chain by calling `wrapped(...)`.
  function wrapper(
    this: unknown,
    wrapped: (...args: unknown[]) => unknown,
    ...args: unknown[]
  ): unknown {
    // TODO: custom behavior before/after the core call.
    return wrapped(...args);
  }

  if (game.modules.get('lib-wrapper')?.active) {
    libWrapper.register(MODULE_ID, target, wrapper, 'WRAPPER');
  } else {
    // Manual fallback: wrap the prototype method directly.
    const proto = Token.prototype;
    const original = proto._draw;
    proto._draw = function (this: unknown, ...args: unknown[]): unknown {
      return wrapper.call(this, original.bind(this), ...args);
    };
  }
}

/** Nudge the GM to install lib-wrapper if it is missing. Called from `ready`. */
export function warnIfLibWrapperMissing(): void {
  if (!game.modules.get('lib-wrapper')?.active && game.user?.isGM) {
    ui.notifications?.warn(
      `${MODULE_TITLE}: the lib-wrapper module is recommended to reduce conflicts with other modules.`,
    );
  }
}
"""

LANG_BASE = """\
{
  "@@MODULE_ID@@.Settings.Enabled.Name": "Enable @@DISPLAY@@",
  "@@MODULE_ID@@.Settings.Enabled.Hint": "Toggle the @@DISPLAY@@ module on or off."@@LANG_EXTRA@@
}
"""

LANG_EXTRA_APP = """\
,
  "@@MODULE_ID@@.Menu.Name": "@@DISPLAY@@",
  "@@MODULE_ID@@.Menu.Label": "Open @@DISPLAY@@",
  "@@MODULE_ID@@.Menu.Hint": "Open the @@DISPLAY@@ panel.",
  "@@MODULE_ID@@.App.Title": "@@DISPLAY@@",
  "@@MODULE_ID@@.App.Body": "This is the @@DISPLAY@@ panel. Replace this with your UI.",
  "@@MODULE_ID@@.App.GMNote": "You are the GM.",
  "@@MODULE_ID@@.App.Refresh": "Refresh\""""

STYLES_CSS = """\
/* All selectors are scoped under the module id to avoid clobbering core or
 * other modules' styles. Keep this prefix on every rule you add. */
.@@MODULE_ID@@-app-body {
  padding: 0.75rem;
}

.@@MODULE_ID@@-app-body h2 {
  margin-top: 0;
}

.@@MODULE_ID@@-gm-note {
  font-style: italic;
  opacity: 0.8;
}

.@@MODULE_ID@@-app-footer {
  display: flex;
  justify-content: flex-end;
  margin-top: 0.5rem;
}
"""

TEST_SETUP = """\
import { vi } from 'vitest';

// Stub the Foundry client globals the module touches so importing src modules
// under Node (where `game`, `Hooks`, `foundry`, ... do not exist) does not throw.
vi.stubGlobal('Hooks', {
  on: vi.fn(),
  once: vi.fn(),
  off: vi.fn(),
  call: vi.fn(),
  callAll: vi.fn(),
});

vi.stubGlobal('game', {
  settings: { register: vi.fn(), registerMenu: vi.fn(), get: vi.fn() },
  i18n: { localize: (k: string) => k, format: (k: string) => k },
  user: { isGM: true },
  modules: { get: () => ({ active: false }) },
});

vi.stubGlobal('ui', {
  notifications: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
});

vi.stubGlobal('foundry', {
  utils: {
    mergeObject: (a: Record<string, unknown>, b: Record<string, unknown>) => ({ ...a, ...b }),
  },
  applications: {
    api: {
      ApplicationV2: class {},
      HandlebarsApplicationMixin: (base: unknown) => base,
    },
  },
});

vi.stubGlobal(
  'Token',
  class {
    _draw(): void {}
  },
);
"""

TEST_MODULE = """\
import { describe, expect, it } from 'vitest';
import { MODULE_ID } from '../src/constants';
import { registerSettings } from '../src/settings';

describe('@@MODULE_ID@@', () => {
  it('exposes the expected module id', () => {
    expect(MODULE_ID).toBe('@@MODULE_ID@@');
  });

  it('registers settings without throwing', () => {
    expect(() => registerSettings()).not.toThrow();
  });
});
"""


# --------------------------------------------------------------------------- #
# Docs templates
# --------------------------------------------------------------------------- #
README = """\
# @@DISPLAY@@

@@DESC@@

A [FoundryVTT](https://foundryvtt.com/) module (v@@FVTT_MIN@@+; verified on
v@@FVTT_VERIFIED@@), built with Vite + TypeScript.

## Install

In Foundry, **Add-on Modules → Install Module → Manifest URL**, paste:

```
https://github.com/@@PUBLISHER@@/@@NAME@@/releases/latest/download/module.json
```

## Development

Requires [bun](https://bun.sh/). The local [foundryvtt-harness](https://github.com/@@PUBLISHER@@/foundryvtt-harness)
(or any local Foundry on `:30000`) is the run/test environment.

```
bun install
just check        # typecheck + build + lint + test (the CI gate)
just dev          # Vite dev server with HMR, proxying to Foundry on :30000
```

To run inside Foundry, build and symlink `dist/` into your Foundry data:

```
just build
ln -s "$(pwd)/dist" "<FoundryData>/Data/modules/@@MODULE_ID@@"
```

(`dist/` is git-ignored and rebuilt; the manifest, lang, styles@@README_TEMPLATES@@ are
copied into it by the build.)

## Releasing

Conventional-commit `feat:` / `fix:` commits drive
[release-please](https://github.com/googleapis/release-please): merging its
release PR tags a version, bumps `package.json` **and** `module.json`, builds the
module, zips `dist/`, and attaches `@@MODULE_ID@@.zip` + `module.json` to the
GitHub release — which is what the manifest URL above resolves to.

## License

MIT — see [LICENSE](LICENSE).
"""

CLAUDE_MD = """\
# @@DISPLAY@@ (`@@MODULE_ID@@`)

@@CLAUDE_INTRO@@

## Layout

| Path | Role |
|------|------|
| `module.json` | The manifest. `id` = `@@MODULE_ID@@` and MUST match the install folder + zip name. release-please bumps `$.version` in lockstep with `package.json`. |
| `src/module.ts` | ESM entry (`esmodules`). Registers hooks; built to `dist/@@MODULE_ID@@.mjs` by Vite. |
| `src/settings.ts` | `game.settings` registration (called from `init`). |
| `src/constants.ts` | `MODULE_ID` / `MODULE_TITLE` — the single source for the id. |
| `src/foundry-shims.d.ts` | Loose ambient types for the Foundry globals. Keep `tsc` green; verify the real API before trusting a shape. |
@@CLAUDE_LAYOUT_EXTRA@@| `lang/en.json` | Localization. Keys are namespaced under `@@MODULE_ID@@.`. |
| `styles/@@MODULE_ID@@.css` | Styles, every selector scoped under `.@@MODULE_ID@@*`. |

## Rules of the road

- **Target the harness-pinned Foundry version.** The local `foundryvtt-harness`
  pins a specific build; module behavior is version-specific. `module.json`
  `compatibility.{minimum,verified}` is the manifest source of truth — keep it in
  sync with what you actually test against, and bump the pin and the code
  together.
- **Verify the Foundry API before patching.** `game.*`, document classes, hooks,
  and the `foundry.applications.*` namespaces change across major versions.
  Check <https://foundryvtt.com/api/> or the live console — not memory.
- **ESM only, paths must byte-match the manifest.** `esmodules` references
  `@@MODULE_ID@@.mjs`; if the Vite output name drifts, the module silently fails
  to load.
- **Do not commit `dist/`.** It is a build artifact (git-ignored); CI builds it
  for releases.
- **`just check` is the gate.** Typecheck + build + lint + test must pass before
  pushing.

## Hooks

`init` registers settings (and patches);@@CLAUDE_HOOKS_EXTRA@@ `ready` runs once
`game.*` is populated. Settings are only readable from `setup` onward.
"""

ADR_0001 = """\
# ADR-0001: Vite + bun + TypeScript toolchain for the FoundryVTT module

- Status: Accepted
- Date: @@DATE@@

## Context

FoundryVTT modules are ESM bundles loaded from a `module.json` manifest. We need
a build that produces a single ESM file at a stable path, copies the manifest
and static assets, type-checks our code, and distributes via GitHub releases.

## Decision

- **Vite library build** (`build.lib`, ESM) → `dist/@@MODULE_ID@@.mjs`, with
  `vite-plugin-static-copy` placing `module.json`, `lang/`, `styles/`@@ADR_TEMPLATES@@
  into `dist/`. The dev server proxies to Foundry on `:30000` with HMR.
- **bun** as the package manager/runner; **biome** for lint + format; **Vitest**
  for unit tests (Foundry globals stubbed in `tests/setup.ts`).
- **TypeScript with local ambient shims** (`src/foundry-shims.d.ts`) rather than
  the `fvtt-types` package, which is git-only and still beta for v13. The shims
  keep the build self-contained and CI-green; richer types can be opted into
  later by switching `tsconfig` `types` to `fvtt-types`.
- **Distribution via GitHub release manifest URL**: `manifest` →
  `releases/latest/download/module.json`, `download` →
  `releases/latest/download/@@MODULE_ID@@.zip`. release-please bumps both
  `package.json` and `module.json` `$.version`; the release job builds + zips +
  attaches the assets.

## Consequences

- No foundryvtt.com submission is required to install by manifest URL (only to be
  listed in the in-app package browser).
- Foundry API types are loose — verify against the live API/docs before relying
  on a shape. This is the deliberate trade for a self-contained, green build.
"""


# --------------------------------------------------------------------------- #
# Generation
# --------------------------------------------------------------------------- #
def build_file_map(ctx: dict[str, str], variant: str) -> dict[str, str]:
    app = variant == "app"
    libwrapper = variant == "libwrapper"

    ctx["BIOME_VERSION"] = BIOME_VERSION
    ctx["TYPESCRIPT_VERSION"] = TYPESCRIPT_VERSION
    ctx["VITE_VERSION"] = VITE_VERSION
    ctx["VITE_STATIC_COPY_VERSION"] = VITE_STATIC_COPY_VERSION
    ctx["VITEST_VERSION"] = VITEST_VERSION

    # module.json relationships (libWrapper recommends) — empty otherwise.
    ctx["RELATIONSHIPS"] = RELATIONSHIPS_LIBWRAPPER if libwrapper else ""

    # Vite static-copy + README/ADR mentions of the templates/ dir (app only).
    ctx["STATIC_COPY_TEMPLATES"] = STATIC_COPY_TEMPLATES if app else ""
    ctx["README_TEMPLATES"] = ", templates" if app else ""
    ctx["ADR_TEMPLATES"] = ", `templates/`" if app else ""

    # module.ts variant wiring.
    if libwrapper:
        ctx["MODULE_IMPORTS"] = (
            "\nimport { registerPatches, warnIfLibWrapperMissing } from './patches';"
        )
        ctx["INIT_BODY_EXTRA"] = "\n  registerPatches();"
        ctx["READY_BODY_EXTRA"] = "\n  warnIfLibWrapperMissing();"
    else:
        ctx["MODULE_IMPORTS"] = ""
        ctx["INIT_BODY_EXTRA"] = ""
        ctx["READY_BODY_EXTRA"] = ""

    # settings.ts variant wiring (registerMenu for the app variant).
    if app:
        ctx["SETTINGS_IMPORTS"] = (
            f"\nimport {{ {ctx['MODULE_CLASS']}App }} from './app';"
        )
        ctx["SETTINGS_MENU"] = subst(SETTINGS_MENU_APP, ctx)
    else:
        ctx["SETTINGS_IMPORTS"] = ""
        ctx["SETTINGS_MENU"] = ""

    # lang extras (app menu/app strings).
    ctx["LANG_EXTRA"] = subst(LANG_EXTRA_APP, ctx) if app else ""

    # CLAUDE.md conditional fragments.
    if app:
        ctx["CLAUDE_INTRO"] = (
            "A FoundryVTT v13 module with an ApplicationV2 UI panel, built with "
            "Vite + TypeScript. The window opens from a settings-menu button "
            "registered in `init`. See ADR-0001 for the toolchain."
        )
        ctx["CLAUDE_LAYOUT_EXTRA"] = (
            f"| `src/app.ts` | The `{ctx['MODULE_CLASS']}App` ApplicationV2 window. |\n"
            "| `templates/app.hbs` | Its Handlebars template (auto-loaded via `static PARTS`). |\n"
        )
        ctx["CLAUDE_HOOKS_EXTRA"] = ""
    elif libwrapper:
        ctx["CLAUDE_INTRO"] = (
            "A FoundryVTT v13 module that patches a core method, built with Vite "
            "+ TypeScript. Patches go through libWrapper when active, with a "
            "manual monkey-patch fallback. See ADR-0001 for the toolchain."
        )
        ctx["CLAUDE_LAYOUT_EXTRA"] = (
            "| `src/patches.ts` | libWrapper-guarded method patch + a manual "
            "fallback. |\n"
        )
        ctx["CLAUDE_HOOKS_EXTRA"] = (
            " `init` also calls `registerPatches()` (libWrapper registration must "
            "happen at/after `init`);"
        )
    else:
        ctx["CLAUDE_INTRO"] = (
            "A FoundryVTT v13 module (settings + lifecycle hooks), built with "
            "Vite + TypeScript. See ADR-0001 for the toolchain."
        )
        ctx["CLAUDE_LAYOUT_EXTRA"] = ""
        ctx["CLAUDE_HOOKS_EXTRA"] = ""

    files: dict[str, str] = {
        "module.json": MODULE_JSON,
        "package.json": PACKAGE_JSON,
        "vite.config.ts": VITE_CONFIG,
        "tsconfig.json": TSCONFIG,
        "biome.json": BIOME_JSON,
        "vitest.config.ts": VITEST_CONFIG,
        ".gitignore": GITIGNORE,
        ".gitattributes": GITATTRIBUTES,
        "release-please-config.json": RP_CONFIG,
        ".release-please-manifest.json": RP_MANIFEST,
        "renovate.json": RENOVATE_JSON,
        ".github/workflows/ci.yml": CI_YML,
        ".github/workflows/release-please.yml": RELEASE_PLEASE_YML,
        ".github/workflows/renovate.yml": RENOVATE_YML,
        "justfile": JUSTFILE,
        "LICENSE": LICENSE,
        "README.md": README,
        "CLAUDE.md": CLAUDE_MD,
        "docs/adr/0001-vite-bun-typescript.md": ADR_0001,
        "src/module.ts": MODULE_TS,
        "src/settings.ts": SETTINGS_TS,
        "src/constants.ts": CONSTANTS_TS,
        "src/foundry-shims.d.ts": FOUNDRY_SHIMS,
        "lang/en.json": LANG_BASE,
        "styles/@@MODULE_ID@@.css": STYLES_CSS,
        "tests/setup.ts": TEST_SETUP,
        "tests/module.test.ts": TEST_MODULE,
    }
    if app:
        files["src/app.ts"] = APP_TS
        files["templates/app.hbs"] = APP_HBS
    if libwrapper:
        files["src/patches.ts"] = PATCHES_TS

    # Substitute tokens in BOTH paths and bodies (the css filename carries one).
    return {subst(path, ctx): subst(body, ctx) for path, body in files.items()}


def main() -> int:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument(
        "--name", required=True, help="GitHub repo name, e.g. foundryvtt-initiative-tweaks"
    )
    p.add_argument(
        "--id",
        default=None,
        help="Foundry module id (lowercase kebab); default: --name without the "
        "leading 'foundryvtt-'",
    )
    p.add_argument(
        "--display", required=True, help='module title, e.g. "Initiative Tweaks"'
    )
    p.add_argument("--desc", required=True, help="one-line description")
    p.add_argument("--variant", choices=VALID_VARIANTS, default="basic")
    p.add_argument("--fvtt-min", default=FVTT_MIN_DEFAULT, help="compatibility.minimum")
    p.add_argument(
        "--fvtt-verified", default=FVTT_VERIFIED_DEFAULT, help="compatibility.verified"
    )
    p.add_argument("--publisher", default=PUBLISHER_DEFAULT)
    p.add_argument("--author", default=AUTHOR_DEFAULT)
    p.add_argument(
        "--dir", default=".", help="parent directory to create the module in (default: cwd)"
    )
    args = p.parse_args()

    ctx = derive(args.name, args.id)
    ctx.update(
        DISPLAY=args.display,
        DESC=args.desc,
        PUBLISHER=args.publisher,
        AUTHOR=args.author,
        FVTT_MIN=args.fvtt_min,
        FVTT_VERIFIED=args.fvtt_verified,
        YEAR=str(datetime.date.today().year),
        DATE=datetime.date.today().isoformat(),
    )

    parent = Path(args.dir).resolve()
    target = parent / args.name
    if target.exists():
        print(f"error: {target} already exists — refusing to overwrite", file=sys.stderr)
        return 1

    file_map = build_file_map(ctx, args.variant)
    for rel, content in file_map.items():
        dest = target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)

    n = len(file_map)
    print(f"\nScaffolded {args.name} (id: {ctx['MODULE_ID']}, {args.variant}) — {n} files in {target}")
    print(
        "\nNext steps:\n"
        f"  cd {target}\n"
        "  git init -b main                # seed main directly (no branch juggling)\n"
        "  bun install                     # TypeScript, Vite, biome, Vitest (writes bun.lock)\n"
        "  just check                      # typecheck + build + lint + test should pass green\n"
        "\nThen:\n"
        + (
            "  - build the panel in src/app.ts + templates/app.hbs\n"
            if args.variant == "app"
            else "  - implement the patch in src/patches.ts (replace the Token._draw example)\n"
            if args.variant == "libwrapper"
            else "  - implement the module logic in src/module.ts + src/settings.ts\n"
        )
        + "  - add the repo to gitops/repositories.tf with release_please = true and a\n"
        "    'foundryvtt' topic (gitops pushes the release-please App credentials)\n"
        "  - or run the /foundryvtt-module orchestrator, which does the gitops wiring\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
