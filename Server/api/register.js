import { saveDevice, removeDevice, isPersistent } from '../lib/store.js';

// The app POSTs here whenever its APNs token, position or radius changes.
export default async function handler(request, response) {
  if (request.method === 'DELETE') {
    const token = request.query?.deviceToken;
    if (!token) return response.status(400).json({ error: 'deviceToken required' });
    await removeDevice(token);
    return response.status(204).end();
  }

  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST, DELETE');
    return response.status(405).json({ error: 'Method not allowed' });
  }

  const body = typeof request.body === 'string' ? safeParse(request.body) : request.body;
  const { deviceToken, latitude, longitude, radiusKm } = body ?? {};

  if (!isHexToken(deviceToken)) {
    return response.status(400).json({ error: 'deviceToken must be a hex APNs token' });
  }
  if (!isFiniteInRange(latitude, -90, 90) || !isFiniteInRange(longitude, -180, 180)) {
    return response.status(400).json({ error: 'latitude/longitude out of range' });
  }
  if (!isFiniteInRange(radiusKm, 1, 500)) {
    return response.status(400).json({ error: 'radiusKm must be between 1 and 500' });
  }

  try {
    const record = await saveDevice({ deviceToken, latitude, longitude, radiusKm });
    return response.status(200).json({ ok: true, persistent: isPersistent(), record });
  } catch (error) {
    return response.status(500).json({ error: error.message });
  }
}

function safeParse(value) {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function isHexToken(value) {
  return typeof value === 'string' && /^[0-9a-fA-F]{64,200}$/.test(value);
}

function isFiniteInRange(value, min, max) {
  return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
}
