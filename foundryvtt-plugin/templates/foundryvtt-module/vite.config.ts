import { defineConfig } from 'vite';
import { viteStaticCopy } from 'vite-plugin-static-copy';

const MODULE_ID = '{{ module_id }}';

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
        { src: 'styles', dest: '.' },
{%- if variant == "app" %}
        { src: 'templates', dest: '.' },
{%- endif %}
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
