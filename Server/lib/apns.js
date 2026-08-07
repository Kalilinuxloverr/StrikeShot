import http2 from 'node:http2';
import crypto from 'node:crypto';

// APNs provider tokens stay valid for an hour; Apple rejects tokens refreshed
// more than once every 20 minutes, so cache and reuse.
let cachedToken = null;
let cachedAt = 0;

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing environment variable ${name}`);
  return value;
}

function base64url(input) {
  return Buffer.from(input).toString('base64url');
}

function providerToken() {
  const now = Date.now();
  if (cachedToken && now - cachedAt < 30 * 60 * 1000) return cachedToken;

  const keyId = requireEnv('APNS_KEY_ID');
  const teamId = requireEnv('APNS_TEAM_ID');
  const privateKey = requireEnv('APNS_PRIVATE_KEY').replace(/\\n/g, '\n');

  const header = base64url(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: Math.floor(now / 1000) }));
  const signature = crypto
    .createSign('SHA256')
    .update(`${header}.${claims}`)
    .sign({ key: privateKey, dsaEncoding: 'ieee-p1363' });

  cachedToken = `${header}.${claims}.${base64url(signature)}`;
  cachedAt = now;
  return cachedToken;
}

/**
 * Sends one alert push. Resolves with { deviceToken, status, reason }.
 * Status 410 means the token is dead and the caller should drop it.
 */
export function sendPush(deviceToken, { title, body, interruptionLevel }) {
  const host = process.env.APNS_HOST || 'https://api.push.apple.com';
  const topic = requireEnv('APNS_TOPIC');
  const payload = JSON.stringify({
    aps: {
      alert: { title, body },
      sound: 'default',
      'interruption-level': interruptionLevel,
    },
  });

  return new Promise((resolve) => {
    const client = http2.connect(host);
    client.on('error', (error) =>
      resolve({ deviceToken, status: 0, reason: error.message })
    );

    const request = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      'apns-topic': topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      authorization: `bearer ${providerToken()}`,
      'content-type': 'application/json',
    });

    let status = 0;
    let responseBody = '';
    request.on('response', (headers) => {
      status = headers[':status'];
    });
    request.setEncoding('utf8');
    request.on('data', (chunk) => {
      responseBody += chunk;
    });
    request.on('end', () => {
      client.close();
      let reason;
      try {
        reason = responseBody ? JSON.parse(responseBody).reason : undefined;
      } catch {
        reason = responseBody || undefined;
      }
      resolve({ deviceToken, status, reason });
    });
    request.on('error', (error) => {
      client.close();
      resolve({ deviceToken, status: 0, reason: error.message });
    });

    request.end(payload);
  });
}
