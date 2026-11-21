import { randomUUID } from 'node:crypto';

/** MeOS ids are lowercase UUIDs throughout (see `AppState.newId`). */
export function newId(): string {
  return randomUUID().toLowerCase();
}
