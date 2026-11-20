const [baseUrl, durationArg = "60", rateArg = "2"] = Bun.argv.slice(2);

if (!baseUrl) {
  console.error("Uso: bun scripts/generate-demo-traffic.js URL [SEGUNDOS=60] [PETICIONES_POR_SEGUNDO=2]");
  process.exit(2);
}

const duration = Number(durationArg);
const rate = Number(rateArg);
if (!Number.isInteger(duration) || duration < 1 || duration > 300) {
  console.error("La duración debe ser un entero entre 1 y 300 segundos.");
  process.exit(2);
}
if (!Number.isFinite(rate) || rate <= 0 || rate > 10) {
  console.error("La tasa debe ser mayor que 0 y no superar 10 peticiones por segundo.");
  process.exit(2);
}

const base = baseUrl.replace(/\/$/, "");
const paths = ["/health", "/ready", "/version", "/api/items", "/ruta-demo-inexistente"];
const statuses = new Map();
const endsAt = Date.now() + duration * 1000;
const interval = 1000 / rate;
let sent = 0;
let failures = 0;

console.log(`Generando tráfico sintético en ${base} durante ${duration}s (máximo ${rate} req/s).`);
console.log("Solo hace GET; la ruta inexistente genera respuestas 404 para demostrar métricas, sin crear datos.");

while (Date.now() < endsAt) {
  const path = paths[sent % paths.length];
  const startedAt = Date.now();
  try {
    const response = await fetch(`${base}${path}`, { signal: AbortSignal.timeout(5000) });
    statuses.set(response.status, (statuses.get(response.status) ?? 0) + 1);
    await response.arrayBuffer();
  } catch (error) {
    failures++;
    console.error(`${path}: ${error.message}`);
  }
  sent++;
  const delay = interval - (Date.now() - startedAt);
  if (delay > 0 && Date.now() < endsAt) await Bun.sleep(delay);
}

console.log(`Peticiones enviadas: ${sent}; fallos de conexión: ${failures}.`);
for (const [status, count] of [...statuses].sort(([a], [b]) => a - b)) {
  console.log(`HTTP ${status}: ${count}`);
}

if (failures > 0) process.exit(1);
