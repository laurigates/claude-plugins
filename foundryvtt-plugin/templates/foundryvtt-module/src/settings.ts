import { MODULE_ID } from './constants';
{%- if variant == "app" %}
import { {{ module_id | pascal_case }}App } from './app';
{%- endif %}

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
{%- if variant == "app" %}
  game.settings.registerMenu(MODULE_ID, 'openApp', {
    name: `${MODULE_ID}.Menu.Name`,
    label: `${MODULE_ID}.Menu.Label`,
    hint: `${MODULE_ID}.Menu.Hint`,
    icon: 'fa-solid fa-table-list',
    type: {{ module_id | pascal_case }}App,
    restricted: false,
  });
{%- endif %}
}

/** Read a boolean module setting. */
export function getSetting(key: string): unknown {
  return game.settings.get(MODULE_ID, key);
}
