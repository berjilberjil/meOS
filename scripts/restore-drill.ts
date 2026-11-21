/**
 * Isolated backup/restore drill. Synthetic data only.
 *
 *   node --experimental-strip-types scripts/restore-drill.ts
 *
 * It creates a small D1-shaped SQLite database, seals a synthetic note and a
 * media object with the real MeOS vault format, takes a SQLite backup, restores
 * it into a fresh database, unlocks the vault with the synthetic passphrase and
 * proves the note/media decrypt. It then tampers with a ciphertext and proves
 * decryption fails closed.
 *
 * It does not touch Cloudflare, production D1, R2 or any real account.
 */
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import {
  deriveKey,
  newSalt,
  open,
  openValue,
  seal,
  sealValue,
  unlockDek,
  type CryptoMeta,
  type SealedEnvelope
} from '../mcp/diet/src/crypto.ts';

const ITERATIONS = 1_000; // synthetic test speed; production vault uses 600k
const PASSPHRASE = 'synthetic-vault-passphrase';
const NOTE_KEY = 'meos.notes';
const MEDIA_AAD = 'event-media:drill-object';
const NOTE = { title: 'Synthetic note', body: 'backup restore drill', amount: 42 };

async function buildVault(): Promise<{ dek: Buffer; meta: CryptoMeta }> {
  const dek = randomBytes(32);
  const passSalt = newSalt();
  const recoverySalt = newSalt();
  const kek = await deriveKey(PASSPHRASE, passSalt, ITERATIONS);
  const recovery = await deriveKey('synthetic-recovery-code', recoverySalt, ITERATIONS);
  const check = Buffer.from('myos.vault.check.v1');
  const meta: CryptoMeta = {
    v: 1,
    kdf: 'pbkdf2-sha256',
    iterations: ITERATIONS,
    passSalt: passSalt.toString('base64'),
    recoverySalt: recoverySalt.toString('base64'),
    wrappedByPass: seal(dek, kek, Buffer.from('wrap:pass')),
    wrappedByRecovery: seal(dek, recovery, Buffer.from('wrap:recovery')),
    check: seal(check, dek, Buffer.from('check'))
  };
  return { dek, meta };
}

function createDb(path: string, meta: CryptoMeta, noteEnvelope: SealedEnvelope) {
  const db = new DatabaseSync(path);
  db.exec(`
    create table users (id integer primary key, username text, password_hash text);
    create table app_state (
      user_id integer not null,
      key text not null,
      value text not null,
      updated_at text not null,
      primary key (user_id, key)
    );
    insert into users (id, username, password_hash) values (1, 'synthetic', 'v3:test');
  `);
  const insert = db.prepare('insert into app_state (user_id, key, value, updated_at) values (?, ?, ?, ?)');
  insert.run(1, 'meos.crypto', JSON.stringify(meta), new Date().toISOString());
  insert.run(1, NOTE_KEY, JSON.stringify(noteEnvelope), new Date().toISOString());
  return db;
}

async function main() {
  const dir = mkdtempSync(join(tmpdir(), 'meos-restore-drill-'));
  const source = join(dir, 'source.sqlite');
  const backup = join(dir, 'backup.sqlite');
  const restored = join(dir, 'restored.sqlite');
  const mediaPath = join(dir, 'event-media-ciphertext');

  const { dek, meta } = await buildVault();
  const noteEnvelope = sealValue(Buffer.from(JSON.stringify(NOTE), 'utf8'), dek, NOTE_KEY);
  const db = createDb(source, meta, noteEnvelope);

  // Synthetic R2 object: ciphertext bytes on disk, as the Worker stores them.
  const media = Buffer.from('synthetic event photo bytes', 'utf8');
  const mediaSealed = seal(media, dek, Buffer.from(MEDIA_AAD));
  writeFileSync(mediaPath, Buffer.from(mediaSealed, 'base64'));
  db.exec(`VACUUM INTO '${backup.replaceAll("'", "''")}'`);
  db.close();

  // Restore into a fresh database, exactly as a D1 import would.
  const restoreDb = new DatabaseSync(backup);
  const rows = restoreDb.prepare('select key, value from app_state where user_id = 1').all() as Array<{
    key: string;
    value: string;
  }>;
  const storedMeta = rows.find((r) => r.key === 'meos.crypto');
  const storedNote = rows.find((r) => r.key === NOTE_KEY);
  if (!storedMeta || !storedNote) throw new Error('restored database is missing vault state');
  const parsedMeta = JSON.parse(storedMeta.value) as CryptoMeta;
  const restoredDek = await unlockDek(parsedMeta, PASSPHRASE);
  const envelope = JSON.parse(storedNote.value) as SealedEnvelope;
  const plain = JSON.parse(openValue(envelope, restoredDek, NOTE_KEY).toString('utf8'));
  if (plain.body !== NOTE.body) throw new Error('note did not decrypt to the original value');

  // A malformed/tampered ciphertext must fail, not return partial plaintext.
  const tampered = { ...envelope, ct: envelope.ct.slice(0, -4) + (envelope.ct.endsWith('AAAA') ? 'BBBB' : 'AAAA') };
  let rejected = false;
  try {
    openValue(tampered, restoredDek, NOTE_KEY);
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error('tampered ciphertext was accepted');

  // R2 restore: copy the opaque object and decrypt with the restored DEK.
  const mediaBytes = readFileSync(mediaPath);
  const mediaPlain = open(mediaBytes.toString('base64'), restoredDek, Buffer.from(MEDIA_AAD));
  if (!mediaPlain.equals(media)) throw new Error('restored media did not decrypt');

  restoreDb.exec(`VACUUM INTO '${restored.replaceAll("'", "''")}'`);
  restoreDb.close();

  console.log(JSON.stringify({
    ok: true,
    database: 'D1-shaped SQLite backup restored',
    stateRows: rows.length,
    vaultUnlocked: true,
    noteDecrypted: true,
    tamperRejected: true,
    mediaDecrypted: true,
    artifacts: dir
  }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
