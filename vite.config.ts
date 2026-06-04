import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  server: {
    host: process.env.VITE_RUBY_HOST || '0.0.0.0',
    port: Number(process.env.VITE_RUBY_PORT || 3036),
    strictPort: true,
    allowedHosts: ['vite', 'localhost', '127.0.0.1'],
    hmr: {
      host: process.env.VITE_RUBY_HMR_HOST || 'localhost',
      port: Number(process.env.VITE_RUBY_PORT || 3036),
      protocol: 'ws',
    },
    watch: {
      usePolling: process.env.CHOKIDAR_USEPOLLING === 'true',
      ignored: [
        '**/node_modules/**',
        '**/public/packs/**',
        '**/.git/**',
        '**/tmp/**',
        '**/log/**',
        '**/coverage/**',
        '**/vendor/**',
      ],
    },
  },
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
});
