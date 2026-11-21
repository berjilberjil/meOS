import { createHmac } from 'node:crypto';

/**
 * TOTP (RFC 6238) for the gateway's own MeOS login.
 *
 * The gateway is a trusted local process that already holds the vault
 * passphrase. If the owner enables MFA, the gateway needs the TOTP seed to sign
 * in unattended; `MEOS_MCP_MFA_SECRET` is that seed. It is not sent to any AI
 * client and is never logged.
 */

const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function decodeBase32(text: string): Buffer {
  const clean = text.toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0;
  let acc = 0;
  const out: number[] = [];
  for (const ch of clean) {
    const v = BASE32.indexOf(ch);
    if (v < 0) continue;
    acc = (acc << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((acc >>> bits) & 0xff);
    }
  }
  return Buffer.from(out);
}

export function totp(secret: string, now = Date.now(), stepSeconds = 30, digits = 6): string {
  const counter = Math.floor(now / 1000 / stepSeconds);
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(counter));
  const mac = createHmac('sha1', decodeBase32(secret)).update(buf).digest();
  const offset = mac[mac.length - 1]! & 0x0f;
  const code =
    ((mac[offset]! & 0x7f) << 24) |
    ((mac[offset + 1]! & 0xff) << 16) |
    ((mac[offset + 2]! & 0xff) << 8) |
    (mac[offset + 3]! & 0xff);
  return String(code % 10 ** digits).padStart(digits, '0');
}
