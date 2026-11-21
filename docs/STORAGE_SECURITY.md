# Storage security

MeOS stores media in a **private Cloudflare R2 bucket** (`meos-media`). There is no public bucket, no
public object URL, and no anonymous read path.

## 1. Key layout

```
body-photos/<user id>/<date>__<id>.jpg      # client-sealed progress/body photos
event-media/<user id>/<id>                  # client-sealed event photos/videos
```

The user id comes from the verified session, never from a request field. Object ids are validated:
`[A-Za-z0-9._-]{1,200}`, not `.`/`..`, which prevents path traversal into another prefix.

## 2. Upload

| Control | Body photos | Event media |
|---|---|---|
| Auth | session | session |
| Per-user rate | 30/min | 30/min |
| Object cap | 15 MB | 60 MB |
| Request cap | 21 MB | 81 MB |
| Per-account quota | 1.5 GB (shared R2 free tier) | same |
| Content | AES-GCM ciphertext from the client | AES-GCM ciphertext |
| Content-Type | `application/octet-stream` | `application/octet-stream` |
| Validation | id/date/base64 length before decode | id/base64 length before decode |
| Audit | kind + bytes, no id | kind + bytes, no id |

The server does not parse images, execute files, or trust a MIME type. A malicious upload is just an
opaque blob; it cannot become a server-side code path. The client decrypts only what it uploaded or
downloaded for its own account.

## 3. Download

1. Session must resolve to a user.
2. The key is built as `<prefix>/<user id>/<id>`; the client cannot request another prefix.
3. `signObjects()` makes a SigV4 GET URL valid for **600 seconds**.
4. R2 serves the ciphertext; the client decrypts with the vault DEK and the per-id AAD.

No signed URL is returned to an MCP client. Body-photo tools return metadata only; event media tools return
counts/ids, not bytes or URLs.

## 4. Deletion

- The app first captures the object/metadata in the recycle bin (`meos.trash`), then deletes the R2 object.
- Delete routes are `DELETE /api/body-photos/<id>` and `DELETE /api/event-media/<id>`, both session-scoped
  and prefixed by the user id.
- Purging the recycle bin releases the held R2 keys via the app/server; a restore before purge keeps the
  object.
- Account deletion is not exposed as an API today; a full wipe is an operator procedure with a backup.

## 5. Configuration

- R2 API token scoped to the bucket, not account-wide.
- `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` are Worker secrets/env only.
- The R2 `MEDIA` binding is used for list/delete/put; the S3 API is used only for signing.
- Bucket must remain private; do not enable a public `r2.dev` domain or a custom public domain.

## 6. Backups

R2 is not included in the D1 export. Copy objects with `rclone`/S3 tooling, encrypt the copy, and store it
separately; see [`BACKUP.md`](BACKUP.md). A D1 restore without R2 gives back the module JSON but not the
photos.

## 7. Verification

- `apps/api/src/lib/server/media.test.ts` — id/base64 caps and traversal rejection.
- `apps/api/src/lib/server/presign.test.ts` — SigV4 URL shape against the AWS SDK oracle.
- Manual: copy a signed URL, wait 10 minutes, retry → expired; change the user id in a key → no object;
  `curl` the object URL without a signature → refused.
- D1 inspection: body/event media rows are not in D1; only ciphertext objects in R2.

## 8. Residual

- A signed URL is a bearer capability for its 10-minute lifetime. Do not paste it into a shared chat or
  logs.
- R2 account compromise can delete objects (availability), but content stays ciphertext without the DEK.
- A client that is unlocked can read its own media; that is the intended trust boundary.
