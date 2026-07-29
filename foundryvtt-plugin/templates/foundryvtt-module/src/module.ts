import { MODULE_ID, MODULE_TITLE } from './constants';
import { registerSettings } from './settings';
{%- if variant == "libwrapper" %}
import { registerPatches, warnIfLibWrapperMissing } from './patches';
{%- endif %}

/** Namespaced console logger so module messages are easy to filter. */
function log(...args: unknown[]): void {
  console.log(`${MODULE_TITLE} |`, ...args);
}

// `init` — register settings and wrap methods. `game` data is NOT populated yet.
Hooks.once('init', () => {
  log(`Initializing ${MODULE_ID}`);
  registerSettings();
{%- if variant == "libwrapper" %}
  registerPatches();
{%- endif %}
});

// `ready` — the world and `game.*` are fully populated.
Hooks.once('ready', () => {
  log('Ready');
{%- if variant == "libwrapper" %}
  warnIfLibWrapperMissing();
{%- endif %}
});
