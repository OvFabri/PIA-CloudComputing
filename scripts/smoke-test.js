const [baseUrl, expectedSha, expectedVersion] = Bun.argv.slice(2);

if (!baseUrl || !expectedSha || !expectedVersion) {
  console.error("Uso: bun scripts/smoke-test.js URL SHA_COMPLETO VERSION");
  process.exit(2);
}

const base = baseUrl.replace(/\/$/, "");
let lastError = "sin respuesta";

for (let attempt = 1; attempt <= 15; attempt++) {
  try {
    const health = await fetch(`${base}/health`, { signal: AbortSignal.timeout(5000) });
    if (!health.ok) throw new Error(`/health devolvió HTTP ${health.status}`);

    const response = await fetch(`${base}/version`, {
      cache: "no-store",
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`/version devolvió HTTP ${response.status}`);

    const body = await response.json();
    if (body.commit_sha !== expectedSha || body.version !== expectedVersion) {
      throw new Error(`versión recibida ${body.version}/${body.commit_sha}`);
    }

    console.log(`Smoke test OK: ${body.version} ${body.commit_sha}`);
    process.exit(0);
  } catch (error) {
    lastError = error.message;
    if (attempt < 15) await Bun.sleep(2000);
  }
}

console.error(`Smoke test falló después de 15 intentos: ${lastError}`);
process.exit(1);
