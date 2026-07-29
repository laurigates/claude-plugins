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
