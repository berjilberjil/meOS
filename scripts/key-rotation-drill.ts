/**
 * Synthetic key-rotation drill. No production access.
 *
 * Proves the vault's current primitives can:
 *   - re-wrap the same DEK under a new passphrase without touching ciphertext;
 *   - re-wrap under a new recovery code and invalidate the old one;
 *   - re-encrypt state/media under a new DEK (the offline rotation procedure).
 *
 *   node --experimental-strip-types scripts/key-rotation-drill.ts
 */
import { randomBytes } from 'node:crypto';
import {
  deriveKey,
  newSalt,
  normalizeRecoveryCode,
  open,
  openValue,
  seal,
  sealValue,
  unlockDek,
  unlockDekWithRecovery,
  type CryptoMeta
} from '../mcp/diet/src/crypto.ts';

const ITERATIONS = 1_000;
const OLD_PASS = 'old-synthetic-passphrase';
const NEW_PASS = 'new-synthetic-passphrase';
const OLD_RECOVERY = 'OLD-RECOVERY-CODE';
const NEW_RECOVERY = 'NEW-RECOVERY-CODE';
const NOTE_KEY = 'meos.notes';
const NOTE = Buffer.from(JSON.stringify({ title: 'rotation drill', value: 7 }), 'utf8');
const MEDIA_AAD = 'event-media:rotation-object';
const MEDIA = Buffer.from('synthetic media bytes', 'utf8');

async function vault() {
  const dek = randomBytes(32);
  const passSalt = newSalt();
  const recoverySalt = newSalt();
  const kek = await deriveKey(OLD_PASS, passSalt, ITERATIONS);
  const rek = await deriveKey(normalizeRecoveryCode(OLD_RECOVERY), recoverySalt, ITERATIONS);
  const check = Buffer.from('myos.vault.check.v1');
  const meta: CryptoMeta = {
    v: 1,
    kdf: 'pbkdf2-sha256',
    iterations: ITERATIONS,
    passSalt: passSalt.toString('base64'),
    recoverySalt: recoverySalt.toString('base64'),
    wrappedByPass: seal(dek, kek, Buffer.from('wrap:pass')),
    wrappedByRecovery: seal(dek, rek, Buffer.from('wrap:recovery')),
    check: seal(check, dek, Buffer.from('check'))
  };
  return { dek, meta };
}

async function main() {
  const { dek, meta } = await vault();
  const noteEnvelope = sealValue(NOTE, dek, NOTE_KEY);
  const mediaSealed = seal(MEDIA, dek, Buffer.from(MEDIA_AAD));

  // 1. Passphrase re-wrap: same DEK, new salt/KEK.
  const newPassSalt = newSalt();
  const newKek = await deriveKey(NEW_PASS, newPassSalt, ITERATIONS);
  const passRotated: CryptoMeta = {
    ...meta,
    passSalt: newPassSalt.toString('base64'),
    wrappedByPass: seal(dek, newKek, Buffer.from('wrap:pass'))
  };
  const afterPass = await unlockDek(passRotated, NEW_PASS);
  if (!afterPass.equals(dek)) throw new Error('passphrase rotation changed the DEK');
  let oldPassRejected = false;
  try { await unlockDek(passRotated, OLD_PASS); } catch { oldPassRejected = true; }
  if (!oldPassRejected) throw new Error('old passphrase still unlocks after rotation');

  // 2. Recovery re-wrap: same DEK, new code.
  const newRecoverySalt = newSalt();
  const newRek = await deriveKey(normalizeRecoveryCode(NEW_RECOVERY), newRecoverySalt, ITERATIONS);
  const recoveryRotated: CryptoMeta = {
    ...passRotated,
    recoverySalt: newRecoverySalt.toString('base64'),
    wrappedByRecovery: seal(dek, newRek, Buffer.from('wrap:recovery'))
  };
  const afterRecovery = await unlockDekWithRecovery(recoveryRotated, NEW_RECOVERY);
  if (!afterRecovery.equals(dek)) throw new Error('recovery rotation changed the DEK');
  let oldRecoveryRejected = false;
  try { await unlockDekWithRecovery(recoveryRotated, OLD_RECOVERY); } catch { oldRecoveryRejected = true; }
  if (!oldRecoveryRejected) throw new Error('old recovery code still unlocks after rotation');

  // 3. Data-key rotation drill: new DEK, re-seal note + media.
  const nextDek = randomBytes(32);
  const noteRotated = sealValue(NOTE, nextDek, NOTE_KEY);
  const mediaRotated = seal(MEDIA, nextDek, Buffer.from(MEDIA_AAD));
  const notePlain = openValue(noteRotated, nextDek, NOTE_KEY);
  if (!notePlain.equals(NOTE)) throw new Error('re-sealed note did not decrypt');
  const mediaBack = open(mediaRotated, nextDek, Buffer.from(MEDIA_AAD));
  if (!mediaBack.equals(MEDIA)) throw new Error('re-sealed media did not decrypt');
  let oldDekRejected = false;
  try { openValue(noteRotated, dek, NOTE_KEY); } catch { oldDekRejected = true; }
  if (!oldDekRejected) throw new Error('old DEK still opens re-sealed state');

  // Existing ciphertext remains valid after only a passphrase/recovery rewrap.
  if (!openValue(noteEnvelope, afterRecovery, NOTE_KEY).equals(NOTE)) {
    throw new Error('existing ciphertext broke during wrap rotation');
  }
  const mediaBackOld = open(mediaSealed, afterRecovery, Buffer.from(MEDIA_AAD));
  if (!mediaBackOld.equals(MEDIA)) throw new Error('existing media broke during wrap rotation');

  console.log(JSON.stringify({
    ok: true,
    passphraseRewrap: true,
    oldPassphraseRejected: true,
    recoveryRewrap: true,
    oldRecoveryRejected: true,
    existingCiphertextPreserved: true,
    dataKeyReencryptionDrill: true,
    oldDekRejectedAfterReencrypt: true
  }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
