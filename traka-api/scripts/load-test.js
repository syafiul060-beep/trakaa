#!/usr/bin/env node
/**
 * Load test sederhana untuk traka-api
 * Uji /health dan /api/driver dengan concurrent requests
 *
 * Jalankan: node scripts/load-test.js [baseUrl] [concurrent] [durationSec]
 * Contoh: node scripts/load-test.js http://localhost:3001 50 30
 *
 * Pastikan traka-api sudah berjalan sebelum load test.
 */
const baseUrl = process.argv[2] || "http://localhost:3001";
const concurrent = parseInt(process.argv[3] || "50", 10);
const durationSec = parseInt(process.argv[4] || "30", 10);

async function request(url) {
  const start = Date.now();
  try {
    const res = await fetch(url);
    const body = await res.text();
    return { ok: res.ok, status: res.status, ms: Date.now() - start };
  } catch (err) {
    return { ok: false, status: 0, ms: Date.now() - start, error: err.message };
  }
}

async function runLoadTest() {
  console.log(`Load test: ${baseUrl}`);
  console.log(`Concurrent: ${concurrent}, Duration: ${durationSec}s\n`);

  const endAt = Date.now() + durationSec * 1000;
  let total = 0;
  let success = 0;
  const latencies = [];

  while (Date.now() < endAt) {
    const batch = Array(concurrent)
      .fill()
      .map(() => request(`${baseUrl}/health`));
    const results = await Promise.all(batch);
    total += results.length;
    success += results.filter((r) => r.ok).length;
    results.forEach((r) => latencies.push(r.ms));
  }

  latencies.sort((a, b) => a - b);
  const p50 = latencies[Math.floor(latencies.length * 0.5)] ?? 0;
  const p95 = latencies[Math.floor(latencies.length * 0.95)] ?? 0;
  const p99 = latencies[Math.floor(latencies.length * 0.99)] ?? 0;

  console.log("--- Hasil ---");
  console.log(`Total requests: ${total}`);
  console.log(`Success: ${success} (${((success / total) * 100).toFixed(1)}%)`);
  console.log(`Latency p50: ${p50}ms, p95: ${p95}ms, p99: ${p99}ms`);
  console.log(`RPS: ${(total / durationSec).toFixed(0)}`);
}

runLoadTest().catch((e) => {
  console.error(e);
  process.exit(1);
});
