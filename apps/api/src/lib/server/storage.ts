import { env } from '$env/dynamic/private';
import { AsyncLocalStorage } from 'node:async_hooks';
import { S3Client, PutObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

// Cloudflare R2 (S3-compatible) client for all private media — progress
// photos today, journal/belongings media later. The bucket isn't
// auto-created: create it once via the Cloudflare dashboard or
// `wrangler r2 bucket create <name>`.
//
// Env vars (server-only, never used client-side):
//   R2_ACCOUNT_ID          Cloudflare account id
//   R2_ACCESS_KEY_ID       R2 API token's S3 access key id
//   R2_SECRET_ACCESS_KEY   R2 API token's S3 secret access key
//   R2_BUCKET              bucket name, e.g. "myos-media"

/// Minimal structural view of the R2 binding we use.
export interface R2Bucket {
  list(options?: { prefix?: string; cursor?: string }): Promise<{
    objects: { key: string; uploaded?: Date; size?: number }[];
    truncated: boolean;
    cursor?: string;
  }>;
  delete(keys: string | string[]): Promise<void>;
}

/// The R2 binding arrives per-request on `platform.env`, exactly like D1, so it
/// travels the same AsyncLocalStorage route (see lib/server/db.ts).
///
/// Why a binding and not the S3 client: the AWS SDK deserialises S3's XML
/// responses with `DOMParser`, which does not exist in the Workers runtime. Any
/// command that returns an XML body — ListObjectsV2, DeleteObjects — therefore
/// threw `ReferenceError: DOMParser is not defined` and 500'd from the moment
/// this moved off Netlify. PutObject has no XML body, which is why uploads kept
/// working and only reads broke. Signing stays on the S3 client: it builds and
/// signs a URL locally and never parses a response.
const mediaCtx = new AsyncLocalStorage<R2Bucket>();

export function withMedia<T>(bucket: R2Bucket, fn: () => T): T {
  return mediaCtx.run(bucket, fn);
}

function media(): R2Bucket {
  const b = mediaCtx.getStore();
  if (!b) throw new Error('R2 MEDIA binding is not available on this request');
  return b;
}

let cachedClient: S3Client | null = null;

function bucket(): string {
  const name = env.R2_BUCKET;
  if (!name) throw new Error('R2_BUCKET is not set on the server');
  return name;
}

function client(): S3Client {
  if (cachedClient) return cachedClient;
  const accountId = env.R2_ACCOUNT_ID;
  const accessKeyId = env.R2_ACCESS_KEY_ID;
  const secretAccessKey = env.R2_SECRET_ACCESS_KEY;
  if (!accountId || !accessKeyId || !secretAccessKey) {
    throw new Error('R2_ACCOUNT_ID / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY are not set on the server');
  }
  cachedClient = new S3Client({
    region: 'auto',
    endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
    credentials: { accessKeyId, secretAccessKey }
  });
  return cachedClient;
}

/**
 * How much media one account may hold. R2's free tier is 10 GB and it is
 * account-wide, so without a per-user ceiling ~168 max-size uploads — one
 * afternoon — puts the whole deployment into billing.
 */
export const USER_MEDIA_BYTES = 1_500_000_000;

/** Bytes currently stored under a prefix. */
export async function bytesUnder(prefix: string): Promise<number> {
  let total = 0;
  let cursor: string | undefined;
  do {
    const page = await media().list({ prefix, cursor });
    for (const o of page.objects) total += o.size ?? 0;
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return total;
}

/** Whether `incoming` more bytes still fit under this user's ceiling. */
export async function mediaRoomFor(prefix: string, incoming: number): Promise<boolean> {
  return (await bytesUnder(prefix)) + incoming <= USER_MEDIA_BYTES;
}

export async function uploadObject(key: string, bytes: Uint8Array, contentType: string): Promise<void> {
  await client().send(
    new PutObjectCommand({ Bucket: bucket(), Key: key, Body: bytes, ContentType: contentType })
  );
}

/// Objects under `prefix`, with `name` relative to it (mirrors how callers
/// used the old Supabase Storage `list` response).
export async function listObjects(prefix: string): Promise<{ name: string; updatedAt?: string }[]> {
  const out: { name: string; updatedAt?: string }[] = [];
  let cursor: string | undefined;
  do {
    const page = await media().list({ prefix, cursor });
    for (const o of page.objects) {
      const name = o.key.slice(prefix.length);
      if (!/\.jpe?g$/i.test(name)) continue;
      out.push({
        name,
        updatedAt: o.uploaded instanceof Date ? o.uploaded.toISOString() : undefined
      });
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return out;
}

/// One signed GET URL per full object key, valid for `expiresIn` seconds.
export async function signObjects(keys: string[], expiresIn = 3600): Promise<Record<string, string>> {
  const out: Record<string, string> = {};
  await Promise.all(
    keys.map(async (key) => {
      out[key] = await getSignedUrl(client(), new GetObjectCommand({ Bucket: bucket(), Key: key }), {
        expiresIn
      });
    })
  );
  return out;
}

export async function removeObjects(keys: string[]): Promise<void> {
  if (!keys.length) return;
  await media().delete(keys);
}

/// R2 key for one sealed event photo/video. The bytes are AES-GCM ciphertext
/// produced on-device, so an object here is opaque to the server.
export function eventMediaKey(userId: number | string, id: string): string {
  return `event-media/${userId}/${id}`;
}
