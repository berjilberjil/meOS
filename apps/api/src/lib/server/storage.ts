import { env } from '$env/dynamic/private';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  DeleteObjectsCommand
} from '@aws-sdk/client-s3';
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

export async function uploadObject(key: string, bytes: Uint8Array, contentType: string): Promise<void> {
  await client().send(
    new PutObjectCommand({ Bucket: bucket(), Key: key, Body: bytes, ContentType: contentType })
  );
}

/// Objects under `prefix`, with `name` relative to it (mirrors how callers
/// used the old Supabase Storage `list` response).
export async function listObjects(prefix: string): Promise<{ name: string; updatedAt?: string }[]> {
  const res = await client().send(new ListObjectsV2Command({ Bucket: bucket(), Prefix: prefix }));
  return (res.Contents ?? [])
    .map((o) => ({ name: (o.Key ?? '').slice(prefix.length), updatedAt: o.LastModified?.toISOString() }))
    .filter((o) => /\.jpe?g$/i.test(o.name));
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
  await client().send(
    new DeleteObjectsCommand({ Bucket: bucket(), Delete: { Objects: keys.map((Key) => ({ Key })) } })
  );
}
