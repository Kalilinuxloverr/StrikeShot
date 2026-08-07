import { collectStrikes, distanceMeters } from '../lib/blitzortung.js';
import { allDevices, removeDevice, lastAlert, rememberAlert } from '../lib/store.js';
import { sendPush } from '../lib/apns.js';

const IMMEDIATE_METERS = 3000;
const DANGER_METERS = 10000;
const REPEAT_SECONDS = 600;
const RANK = { approaching: 0, danger: 1, immediate: 2 };

// Runs on a schedule (see vercel.json). Samples the live feed, then warns each
// registered device whose radius the storm has entered.
export default async function handler(request, response) {
  if (!isAuthorized(request)) {
    return response.status(401).json({ error: 'Unauthorized' });
  }

  const devices = await allDevices();
  if (devices.length === 0) {
    return response.status(200).json({ devices: 0, strikes: 0, pushed: 0 });
  }

  const strikes = await collectStrikes({ durationMs: Number(process.env.SAMPLE_MS) || 20000 });
  const now = Date.now();
  let pushed = 0;

  for (const device of devices) {
    const distances = strikes
      .map((strike) => distanceMeters(device, strike))
      .filter((meters) => meters <= device.radiusKm * 1000);
    if (distances.length === 0) continue;

    const nearest = Math.min(...distances);
    const kind =
      nearest < IMMEDIATE_METERS ? 'immediate'
      : nearest < DANGER_METERS ? 'danger'
      : 'approaching';

    const previous = await lastAlert(device.deviceToken);
    if (!shouldSend(kind, previous, now)) continue;

    const result = await sendPush(device.deviceToken, message(kind, nearest, distances.length));
    if (result.status === 410) {
      await removeDevice(device.deviceToken);
      continue;
    }
    if (result.status === 200) {
      pushed += 1;
      await rememberAlert(device.deviceToken, { kind, at: now });
    } else {
      console.error('APNs rejected push', result.status, result.reason);
    }
  }

  return response.status(200).json({ devices: devices.length, strikes: strikes.length, pushed });
}

function isAuthorized(request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return true; // Vercel Cron calls are internal; the secret is belt and braces.
  return request.headers.authorization === `Bearer ${secret}`;
}

function shouldSend(kind, previous, now) {
  if (!previous) return true;
  if (RANK[kind] > RANK[previous.kind]) return true; // escalation always gets through
  return now - previous.at > REPEAT_SECONDS * 1000;
}

function message(kind, nearestMeters, count) {
  const km = (nearestMeters / 1000).toFixed(nearestMeters < 10000 ? 1 : 0);
  switch (kind) {
    case 'immediate':
      return {
        title: 'Blitz in unmittelbarer Nähe',
        body: `Einschlag ${km} km entfernt. Geh sofort ins Haus oder ins Auto.`,
        interruptionLevel: 'time-sensitive',
      };
    case 'danger':
      return {
        title: 'Gewitter über dir',
        body: `Nächster Einschlag ${km} km. 30/30-Regel beachten.`,
        interruptionLevel: 'time-sensitive',
      };
    default:
      return {
        title: 'Gewitter im Radius',
        body: `${count} Blitze, nächster ${km} km entfernt.`,
        interruptionLevel: 'active',
      };
  }
}
