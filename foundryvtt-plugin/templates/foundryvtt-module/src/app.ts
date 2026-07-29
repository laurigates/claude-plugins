import { MODULE_ID, MODULE_TITLE } from './constants';

const { ApplicationV2, HandlebarsApplicationMixin } = foundry.applications.api;

/**
 * A minimal Foundry v13 ApplicationV2 window using HandlebarsApplicationMixin.
 * Templates listed in `static PARTS` are auto-loaded by the mixin on render.
 * Open it with `new {{ module_id | pascal_case }}App().render(true)`.
 */
export class {{ module_id | pascal_case }}App extends HandlebarsApplicationMixin(ApplicationV2) {
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
      refresh: {{ module_id | pascal_case }}App.#onRefresh,
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
    this: {{ module_id | pascal_case }}App,
    _event: Event,
    _target: HTMLElement,
  ): Promise<void> {
    await this.render();
  }
}
