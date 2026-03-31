#!/usr/bin/env node
/**
 * Hitung POST /api/driver/location dari file HAR (tanpa dependensi npm).
 * Uso: node scripts/count_har_driver_location.mjs path/to/file.har
 * Opsi: --patch --delete  (hitung PATCH/DELETE /api/driver/status)
 *       --verbose           (daftar tiap URL)
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const flags = new Set(process.argv.slice(2).filter((a) => a.startsWith("--")));

const path = args[0];
if (!path) {
  console.error("Usage: node scripts/count_har_driver_location.mjs <file.har> [--patch] [--delete] [--verbose]");
  process.exit(1);
}

const locNeedle = "/api/driver/location";
const statusPath = "/api/driver/status";

const raw = readFileSync(resolve(path), "utf8");
const har = JSON.parse(raw);
const entries = har?.log?.entries;
if (!Array.isArray(entries)) {
  console.error("HAR tidak punya log.entries");
  process.exit(1);
}

const posts = [];
let patchCount = 0;
let deleteCount = 0;

for (const e of entries) {
  const req = e.request;
  if (!req) continue;
  const method = String(req.method || "");
  const url = String(req.url || "");
  const u = url.toLowerCase();

  if (method === "POST" && u.includes(locNeedle.toLowerCase())) {
    posts.push({ started: new Date(e.startedDateTime), url });
  }
  if (flags.has("--patch") && method === "PATCH" && u.includes(statusPath)) patchCount++;
  if (flags.has("--delete") && method === "DELETE" && u.includes(statusPath)) deleteCount++;
}

console.log("HAR:", resolve(path));
console.log("POST *" + locNeedle + "* :", posts.length);
if (posts.length === 0) {
  process.exit(0);
}

const byMinute = new Map();
for (const p of posts) {
  const k = p.started.toISOString().slice(0, 16).replace("T", " ");
  byMinute.set(k, (byMinute.get(k) || 0) + 1);
}
console.log("\nPer menit (UTC):");
for (const [k, c] of [...byMinute.entries()].sort()) {
  console.log("  " + k + "  " + c);
}

posts.sort((a, b) => a.started - b.started);
const first = posts[0].started;
const last = posts[posts.length - 1].started;
const spanMin = Math.max(1, Math.ceil((last - first) / 60000));
const avg = (posts.length / spanMin).toFixed(2);
console.log("\nJendela:", first.toISOString(), "..", last.toISOString(), "(~" + spanMin + " menit) => rata-rata ~" + avg + " POST/menit");

let maxBurst = 0;
const times = posts.map((p) => p.started.getTime());
for (let i = 0; i < times.length; i++) {
  let c = 0;
  for (let j = i; j < times.length; j++) {
    if (times[j] - times[i] <= 10000) c++;
    else break;
  }
  if (c > maxBurst) maxBurst = c;
}
console.log("Puncak burst (sliding 10 dtk):", maxBurst);

if (flags.has("--patch")) console.log("PATCH *" + statusPath + "* :", patchCount);
if (flags.has("--delete")) console.log("DELETE *" + statusPath + "* :", deleteCount);

if (flags.has("--verbose")) {
  console.log("\nURLs (tanpa query):");
  for (const p of posts) {
    const short = p.url.replace(/\?.*$/, "");
    console.log("  " + p.started.toISOString() + "  " + short);
  }
}
