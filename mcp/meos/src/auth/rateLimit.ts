import { errors } from '../utils/errors.ts';

interface Bucket {
  hits: number[];
}

/** Sliding-window limiter, per client id. In-memory by design: one process. */
export class RateLimiter {
  private readonly buckets = new Map<string, Bucket>();
  private readonly windowMs: number;
  private readonly max: number;
  private readonly now: () => number;

  constructor(windowMs: number, max: number, now: () => number = Date.now) {
    this.windowMs = windowMs;
    this.max = max;
    this.now = now;
  }

  /** Throws `rate_limited` when the client is over budget. */
  take(clientId: string): void {
    const now = this.now();
    const bucket = this.buckets.get(clientId) ?? { hits: [] };
    bucket.hits = bucket.hits.filter((t) => now - t < this.windowMs);
    if (bucket.hits.length >= this.max) {
      const oldest = bucket.hits[0] ?? now;
      const retry = Math.max(1, Math.ceil((this.windowMs - (now - oldest)) / 1000));
      this.buckets.set(clientId, bucket);
      throw errors.rateLimited(retry);
    }
    bucket.hits.push(now);
    this.buckets.set(clientId, bucket);
  }
}
