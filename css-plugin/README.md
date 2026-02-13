# css-plugin

CSS tooling skills for Lightning CSS transpilation/minification and UnoCSS atomic utility generation.

## Skills

| Skill | Description |
|-------|-------------|
| Lightning CSS | CSS transpilation, bundling, minification, and browser targeting via Lightning CSS |
| UnoCSS | On-demand atomic CSS engine with presets, custom rules, and framework integrations |

## Use Cases

- **Lightning CSS**: Replace PostCSS/autoprefixer pipeline, configure Vite CSS processing, enable CSS modules, set browser targets, minify CSS for production
- **UnoCSS**: Set up utility-first CSS, configure presets (wind3/wind4, icons, typography), generate atomic stylesheets, integrate with Vite/Nuxt/Astro

## Complementary Pipeline

Lightning CSS and UnoCSS work together in a Vite pipeline:

1. **UnoCSS** (Vite plugin) scans source files and generates atomic utility CSS
2. **Lightning CSS** (Vite transformer) transpiles, prefixes, and minifies all CSS

```typescript
// vite.config.ts
import UnoCSS from 'unocss/vite'
import browserslist from 'browserslist'
import { browserslistToTargets } from 'lightningcss'

export default defineConfig({
  plugins: [UnoCSS()],
  css: {
    transformer: 'lightningcss',
    lightningcss: {
      targets: browserslistToTargets(browserslist('>= 0.25%'))
    }
  },
  build: { cssMinify: 'lightningcss' }
})
```
