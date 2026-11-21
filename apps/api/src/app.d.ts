declare global {
  namespace App {
    interface Locals {
      user?: { id: number; username: string };
      /** The raw session cookie for this request. Server-only; never serialized. */
      sessionToken?: string;
      /** A non-secret public id for the current session. */
      sessionId?: string;
      /** ISO timestamp when this session was created (for fresh-session checks). */
      sessionCreatedAt?: string;
    }
  }
}

export {};
