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
