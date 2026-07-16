import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

function revisionPlugin() {
  let revision = Date.now()

  return {
    name: 'cmdop-demo-revision',
    configureServer(server) {
      server.watcher.on('all', (event, path) => {
        if (event !== 'addDir' && !path.includes('node_modules')) {
          revision = Date.now()
        }
      })
      server.middlewares.use('/__demo_revision', (_request, response) => {
        response.setHeader('Content-Type', 'application/json')
        response.setHeader('Cache-Control', 'no-store')
        response.end(JSON.stringify({ revision }))
      })
    },
  }
}

const hmrClientPort = Number(process.env.VITE_HMR_CLIENT_PORT || 0)

export default defineConfig({
  plugins: [react(), revisionPlugin()],
  server: {
    host: '0.0.0.0',
    port: Number(process.env.DEMO_PORT || 5173),
    strictPort: true,
    watch: {
      usePolling: process.env.VITE_USE_POLLING !== 'false',
      interval: Number(process.env.VITE_POLL_INTERVAL_MS || 300),
    },
    hmr: hmrClientPort > 0 ? { clientPort: hmrClientPort } : true,
  },
})
