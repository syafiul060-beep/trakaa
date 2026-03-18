/**
 * PM2 ecosystem config - clustering untuk traka-api
 * Jalankan: pm2 start ecosystem.config.cjs
 * Lihat: pm2 status, pm2 logs
 */
module.exports = {
  apps: [
    {
      name: 'traka-api',
      script: 'src/index.js',
      instances: 'max', // atau angka: 4 (sesuaikan dengan CPU)
      exec_mode: 'cluster',
      env: { NODE_ENV: 'production' },
      max_memory_restart: '500M',
    },
  ],
};
