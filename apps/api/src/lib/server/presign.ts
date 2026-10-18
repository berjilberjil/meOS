/**
 * Presigned R2 GET URLs (AWS SigV4, query-string form) on crypto.subtle.
 *
 * WHY NOT THE AWS SDK: `getSignedUrl` does its SHA-256/HMAC in JavaScript.
 * GET /api/body-photos signs one URL per photo on every media tick (~15s), and
 * that cost 30-110ms CPU per request against the free tier's 10ms cap. Native
 * crypto.subtle does the same work in a fraction of that, and the URLs are
 * byte-for-byte what the SDK produced (see presign.test.ts), so clients see no
 * difference.
 *
 * The SigV4 signing key depends only on the secret and the UTC day, so it is
 * derived once per day per isolate instead of four HMACs per URL.
 */

export interface PresignConfig {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
}

const enc = new TextEncoder();

function hex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('');
}

async function hmac(key: ArrayBuffer | Uint8Array<ArrayBuffer>, data: string): Promise<ArrayBuffer> {
  const k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return crypto.subtle.sign('HMAC', k, enc.encode(data));
}

/** RFC 3986 encoding, which SigV4 requires (encodeURIComponent leaves !'()* alone). */
function uriEncode(s: string): string {
  return encodeURIComponent(s).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());
}

let cachedKey: { id: string; key: Promise<CryptoKey> } | null = null;

/** HMAC key for kSigning = HMAC(HMAC(HMAC(HMAC("AWS4"+secret, day), region), service), "aws4_request"). */
function signingKey(secret: string, day: string): Promise<CryptoKey> {
  const id = `${secret}\n${day}`;
  if (cachedKey?.id === id) return cachedKey.key;
  const key = (async () => {
    let k = await hmac(enc.encode('AWS4' + secret), day);
    for (const part of ['auto', 's3', 'aws4_request']) k = await hmac(k, part);
    return crypto.subtle.importKey('raw', k, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  })();
  cachedKey = { id, key };
  return key;
}

/** One presigned GET URL for `key`, valid for `expiresIn` seconds from `now`. */
export async function presignGet(
  cfg: PresignConfig,
  key: string,
  expiresIn: number,
  now: Date = new Date()
): Promise<string> {
  const host = `${cfg.bucket}.${cfg.accountId}.r2.cloudflarestorage.com`;
  const amzDate = now.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  const day = amzDate.slice(0, 8);
  const scope = `${day}/auto/s3/aws4_request`;
  const path = '/' + key.split('/').map(uriEncode).join('/');

  // Already in sorted order, as the canonical request requires. The checksum
  // mode is what the SDK's GetObject adds by default; kept so URLs are unchanged.
  const params = [
    ['X-Amz-Algorithm', 'AWS4-HMAC-SHA256'],
    ['X-Amz-Content-Sha256', 'UNSIGNED-PAYLOAD'],
    ['X-Amz-Credential', `${cfg.accessKeyId}/${scope}`],
    ['X-Amz-Date', amzDate],
    ['X-Amz-Expires', String(expiresIn)],
    ['X-Amz-SignedHeaders', 'host'],
    ['x-amz-checksum-mode', 'ENABLED'],
    ['x-id', 'GetObject']
  ];
  const qs = (ps: string[][]) => ps.map(([k, v]) => `${uriEncode(k)}=${uriEncode(v)}`).join('&');
  const query = qs(params);

  const canonical = ['GET', path, query, `host:${host}\n`, 'host', 'UNSIGNED-PAYLOAD'].join('\n');
  const toSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    hex(await crypto.subtle.digest('SHA-256', enc.encode(canonical)))
  ].join('\n');
  const sig = hex(await crypto.subtle.sign('HMAC', await signingKey(cfg.secretAccessKey, day), enc.encode(toSign)));
  // The signature slots into sorted position (Signature < SignedHeaders), as the SDK emits it.
  params.splice(5, 0, ['X-Amz-Signature', sig]);
  return `https://${host}${path}?${qs(params)}`;
}
