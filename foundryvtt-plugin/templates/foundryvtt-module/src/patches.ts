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
