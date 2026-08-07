const ENDPOINTS = [1, 2, 3, 4, 5, 6, 7, 8].map((n) => `ws://ws${n}.blitzortung.org:8080`);

/**
 * Blitzortung frames are packed with an LZW variant. Mirrors
 * BlitzortungDecoder.decompress in the app — keep the two in step.
 */
export function decompress(input) {
  const data = String(input);
  if (data.length === 0) return '';

  const dictionary = new Map();
  let previous = data[0];
  let result = previous;
  let code = 256;

  for (let i = 1; i < data.length; i += 1) {
    const currentCode = data.charCodeAt(i);
    let entry;
    if (currentCode < 256) {
      entry = data[i];
    } else if (dictionary.has(currentCode)) {
      entry = dictionary.get(currentCode);
    } else {
      entry = previous + previous.charAt(0);
    }
    result += entry;
    dictionary.set(code, previous + entry.charAt(0));
    code += 1;
    previous = entry;
  }
  return result;
}

export function parseStrike(raw) {
  let payload;
  try {
    payload = JSON.parse(decompress(raw));
  } catch {
    return null;
  }
  const { time, lat, lon } = payload ?? {};
  if (typeof lat !== 'number' || typeof lon !== 'number' || typeof time !== 'number') {
    return null;
  }
  // Blitzortung timestamps are nanoseconds since the epoch.
  return { latitude: lat, longitude: lon, time: new Date(time / 1e6) };
}

/**
 * Opens one endpoint, collects strikes for `durationMs`, then closes.
 * Cron functions cannot hold a socket open, so each run takes a short sample.
 */
export async function collectStrikes({ durationMs = 20000 } = {}) {
  // Imported here, not at module scope, so the pure decoding helpers above stay
  // testable without pulling in a network dependency.
  const { default: WebSocket } = await import('ws');

  return new Promise((resolve) => {
    const strikes = [];
    let index = 0;
    let socket;
    let finished = false;

    const finish = () => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      try {
        socket?.close();
      } catch {
        // already closing
      }
      resolve(strikes);
    };

    const timer = setTimeout(finish, durationMs);

    const connect = () => {
      if (index >= ENDPOINTS.length) return finish();
      const url = ENDPOINTS[index];
      index += 1;
      socket = new WebSocket(url);

      socket.on('open', () => socket.send(JSON.stringify({ a: 111 })));
      socket.on('message', (data) => {
        const strike = parseStrike(data.toString());
        if (strike) strikes.push(strike);
      });
      socket.on('error', () => {
        if (!finished && strikes.length === 0) connect();
      });
      socket.on('close', () => {
        if (!finished && strikes.length === 0) connect();
      });
    };

    connect();
  });
}

export function distanceMeters(a, b) {
  const R = 6371000;
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(b.latitude - a.latitude);
  const dLon = toRad(b.longitude - a.longitude);
  const lat1 = toRad(a.latitude);
  const lat2 = toRad(b.latitude);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(h), Math.sqrt(Math.max(0, 1 - h)));
}
