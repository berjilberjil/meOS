import { describe, it, expect } from 'vitest';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { presignGet, type PresignConfig } from './presign';

// The replacement has to be indistinguishable from what clients got before, so
// the oracle is the SDK itself, at a pinned clock.
const cfg: PresignConfig = {
  accountId: '0123456789abcdef0123456789abcdef',
  accessKeyId: 'AKIDEXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
  bucket: 'meos-media'
};

const sdk = new S3Client({
  region: 'auto',
  endpoint: `https://${cfg.accountId}.r2.cloudflarestorage.com`,
  credentials: { accessKeyId: cfg.accessKeyId, secretAccessKey: cfg.secretAccessKey }
});

function viaSdk(key: string, expiresIn: number, at: Date) {
  return getSignedUrl(sdk, new GetObjectCommand({ Bucket: cfg.bucket, Key: key }), {
    expiresIn,
    signingDate: at
  });
}

describe('presignGet', () => {
  const at = new Date('2026-10-18T04:30:15.123Z');

  it.each([
    'body-photos/1/2026-10-18__AB12-cd.jpg',
    'event-media/1/3F2A9C1E-0000-4000-8000-000000000001',
    "body-photos/1/odd name (1)!'*~.jpg"
  ])('matches the AWS SDK for %s', async (key) => {
    expect(await presignGet(cfg, key, 3600, at)).toBe(await viaSdk(key, 3600, at));
  });

  it('matches across a day boundary (signing key is per-day)', async () => {
    const next = new Date('2026-10-19T00:00:01Z');
    const key = 'body-photos/1/x.jpg';
    expect(await presignGet(cfg, key, 3600, at)).toBe(await viaSdk(key, 3600, at));
    expect(await presignGet(cfg, key, 3600, next)).toBe(await viaSdk(key, 3600, next));
  });
});
