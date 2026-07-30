import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { MODULE_ID } from '../src/constants';

// Foundry installs this module from the GitHub release and loads it out of
// `dist/`, which the build assembles from `module.json` plus the Vite output.
// Nothing else in CI compares the two: `tsc --noEmit`, `vite build`, `biome`,
// and the smoke suite all pass while the manifest points at a file the build
// never emits, or at a release asset the release job never uploads. The only
// symptom is a module that silently fails to load, or an install URL that 404s.
// These assertions are that comparison.

function repoPath(relative: string): string {
  return fileURLToPath(new URL(relative, import.meta.url));
}

function read(relative: string): string {
  return readFileSync(repoPath(relative), 'utf8');
}

const manifest = JSON.parse(read('../module.json'));
const viteConfig = read('../vite.config.ts');
const releaseWorkflow = read('../.github/workflows/release-please.yml');

/** The id the Vite config pins its library output filename to. */
function viteModuleId(): string {
  return viteConfig.match(/const MODULE_ID = '([^']+)'/)?.[1] ?? '';
}

/** The zip basename the release job attaches to the GitHub release. */
function releaseZipName(): string {
  return releaseWorkflow.match(/zip -r \.\.\/(\S+\.zip) \./)?.[1] ?? '';
}

describe('module.json matches the build output', () => {
  it('uses one module id across the manifest, the source, and the Vite config', () => {
    expect(manifest.id).toBe(MODULE_ID);
    expect(viteModuleId()).toBe(manifest.id);
  });

  it('declares the esmodule the Vite library build actually emits', () => {
    expect(manifest.esmodules).toEqual([`${manifest.id}.mjs`]);
  });

  it('declares only asset paths that exist in the repo', () => {
    const declared: string[] = [
      ...(manifest.styles ?? []),
      ...(manifest.languages ?? []).map((lang: { path: string }) => lang.path),
    ];
    expect(declared.length).toBeGreaterThan(0);
    for (const asset of declared) {
      expect(existsSync(repoPath(`../${asset}`)), `declared asset missing: ${asset}`).toBe(true);
    }
  });
});

describe('module.json matches the release assets', () => {
  it('points the manifest URL at the floating latest release', () => {
    expect(manifest.manifest.endsWith('/releases/latest/download/module.json')).toBe(true);
  });

  it('points the download URL at the zip the release job uploads', () => {
    expect(manifest.download.endsWith(`/releases/latest/download/${manifest.id}.zip`)).toBe(true);
    expect(releaseZipName()).toBe(`${manifest.id}.zip`);
  });
});
