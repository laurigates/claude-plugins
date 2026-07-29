import { describe, expect, it } from 'vitest';
import { MODULE_ID } from '../src/constants';
import { registerSettings } from '../src/settings';

describe('{{ module_id }}', () => {
  it('exposes the expected module id', () => {
    expect(MODULE_ID).toBe('{{ module_id }}');
  });

  it('registers settings without throwing', () => {
    expect(() => registerSettings()).not.toThrow();
  });
});
