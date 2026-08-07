import test from 'node:test';
import assert from 'node:assert/strict';
import { decompress, parseStrike, distanceMeters } from '../lib/blitzortung.js';

// The matching packer, so the decoder can be checked without live traffic.
function compress(input) {
  const dictionary = new Map();
  let code = 256;
  let phrase = input[0] ?? '';
  const output = [];

  for (let i = 1; i < input.length; i += 1) {
    const character = input[i];
    if (dictionary.has(phrase + character)) {
      phrase += character;
    } else {
      output.push(phrase.length > 1 ? dictionary.get(phrase) : phrase.charCodeAt(0));
      dictionary.set(phrase + character, code);
      code += 1;
      phrase = character;
    }
  }
  if (phrase !== '') {
    output.push(phrase.length > 1 ? dictionary.get(phrase) : phrase.charCodeAt(0));
  }
  return output.map((value) => String.fromCharCode(value)).join('');
}

test('round-trips plain JSON', () => {
  const payload = '{"time":1723065600000000000,"lat":48.2082,"lon":16.3738}';
  assert.equal(decompress(compress(payload)), payload);
});

test('round-trips repetitive text where the dictionary actually kicks in', () => {
  const payload = 'aaabbbaaabbbaaabbb'.repeat(8);
  assert.equal(decompress(compress(payload)), payload);
});

test('empty input decompresses to empty string', () => {
  assert.equal(decompress(''), '');
});

test('parseStrike converts nanoseconds to a Date', () => {
  const strike = parseStrike(compress('{"time":1723065600000000000,"lat":48.2,"lon":16.3}'));
  assert.ok(strike);
  assert.equal(strike.time.getTime(), 1723065600000);
  assert.equal(strike.latitude, 48.2);
});

test('parseStrike returns null for junk instead of throwing', () => {
  assert.equal(parseStrike('not json at all'), null);
  assert.equal(parseStrike(compress('{"lat":1}')), null);
});

test('distanceMeters matches a known separation', () => {
  const vienna = { latitude: 48.2082, longitude: 16.3738 };
  const graz = { latitude: 47.0707, longitude: 15.4395 };
  const meters = distanceMeters(vienna, graz);
  // Great-circle Vienna–Graz is roughly 145 km.
  assert.ok(meters > 140000 && meters < 150000, `got ${meters}`);
});
