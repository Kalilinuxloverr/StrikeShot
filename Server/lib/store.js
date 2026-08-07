// Device registry.
//
// ponytail: talks the Upstash/Vercel Redis REST protocol directly — no SDK, no
// schema, one hash of deviceToken -> registration JSON. Any Redis from the Vercel
// Marketplace injects KV_REST_API_URL and KV_REST_API_TOKEN and just works. With
// neither set, falls back to process memory so `vercel dev` runs without setup;
// that fallback forgets everything on cold start, which is fine for one phone and
// wrong for many — provision Redis before relying on it.

const HASH_KEY = 'strikeshot:devices';
const memory = new Map();

function restConfig() {
  const url = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
  return url && token ? { url, token } : null;
}

export const isPersistent = () => restConfig() !== null;

async function command(...args) {
  const config = restConfig();
  if (!config) return null;
  const response = await fetch(config.url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(args),
  });
  if (!response.ok) {
    throw new Error(`Redis ${args[0]} failed: ${response.status} ${await response.text()}`);
  }
  const { result } = await response.json();
  return result;
}

/** @param {{deviceToken: string, latitude: number, longitude: number, radiusKm: number}} registration */
export async function saveDevice(registration) {
  const record = { ...registration, updatedAt: new Date().toISOString() };
  if (!isPersistent()) {
    memory.set(registration.deviceToken, record);
    return record;
  }
  await command('HSET', HASH_KEY, registration.deviceToken, JSON.stringify(record));
  return record;
}

export async function allDevices() {
  if (!isPersistent()) {
    return [...memory.entries()]
      .filter(([key]) => !key.startsWith('alert:'))
      .map(([, value]) => value);
  }
  const flat = await command('HGETALL', HASH_KEY);
  if (!flat) return [];
  // HGETALL comes back as [field, value, field, value, ...] over REST.
  const values = Array.isArray(flat)
    ? flat.filter((_, index) => index % 2 === 1)
    : Object.values(flat);
  return values.flatMap((raw) => {
    try {
      return [JSON.parse(raw)];
    } catch {
      return [];
    }
  });
}

export async function removeDevice(deviceToken) {
  if (!isPersistent()) {
    memory.delete(deviceToken);
    return;
  }
  await command('HDEL', HASH_KEY, deviceToken);
}

/** Remembers what a device was last told, so it is not warned every cron tick. */
export async function lastAlert(deviceToken) {
  if (!isPersistent()) return memory.get(`alert:${deviceToken}`) ?? null;
  const raw = await command('GET', `strikeshot:alert:${deviceToken}`);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export async function rememberAlert(deviceToken, alert, ttlSeconds = 3600) {
  if (!isPersistent()) {
    memory.set(`alert:${deviceToken}`, alert);
    return;
  }
  await command('SET', `strikeshot:alert:${deviceToken}`, JSON.stringify(alert), 'EX', ttlSeconds);
}
