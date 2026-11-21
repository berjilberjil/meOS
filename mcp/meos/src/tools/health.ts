import { z } from 'zod';
import {
  STATE_KEYS,
  DEFAULT_FITNESS_PROFILE,
  DEFAULT_PROFILE,
  type ExerciseLog,
  type FitnessDay,
  type FitnessProfile,
  type Profile,
  type SetLog,
  type TrainingState,
  type WorkoutDayLog
} from '../schemas/models.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { paginate } from '../utils/pagination.ts';
import { addDays, assertDateKey, todayKey } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import type { ToolDefinition } from './registry.ts';
import { readObject } from './shared.ts';
import { bmi, calorieTargets, latestWeight } from '../services/nutrition.ts';

const DEFAULT_TRAINING: TrainingState = {
  customExercises: [],
  weekPlan: {},
  dayLog: {},
  programs: [],
  activeProgramId: null,
  migratedWeekPlan: false
};

function sessionVolume(entries: ExerciseLog[] | null | undefined): number {
  return (entries ?? []).reduce(
    (sum, e) => sum + (e.sets ?? []).filter((s) => s.done).reduce((v, s) => v + (s.weightKg ?? 0) * (s.reps ?? 0), 0),
    0
  );
}

function dayLogSummary(date: string, log: WorkoutDayLog) {
  const entries = log.entries ?? [];
  return {
    date,
    title: log.title ?? null,
    done: Boolean(log.done),
    skipped: Boolean(log.skipped),
    rest: Boolean(log.restOverride),
    program_id: log.programId ?? null,
    day_id: log.dayId ?? null,
    exercise_count: entries.length || (log.items ?? []).length,
    completed_sets: entries.reduce((n, e) => n + (e.sets ?? []).filter((s) => s.done).length, 0),
    volume_kg: Math.round(sessionVolume(entries) * 10) / 10,
    has_session: entries.some((e) => (e.sets ?? []).some((s) => s.done))
  };
}

function parseEntries(
  input: Array<{
    exercise_id: string;
    group?: string;
    note?: string;
    sets: Array<{ weight_kg?: number | null; reps: number; done?: boolean }>;
  }>
): ExerciseLog[] {
  return input.map((e) => ({
    id: newId(),
    exerciseId: e.exercise_id.trim(),
    group: e.group?.trim() || 'fullBody',
    note: e.note?.slice(0, 1000) ?? null,
    sets: e.sets.map<SetLog>((s) => ({
      id: newId(),
      weightKg: s.weight_kg ?? null,
      reps: Math.max(0, Math.round(s.reps)),
      done: s.done !== false
    }))
  }));
}

const EntriesShape = z
  .array(
    z.object({
      exercise_id: z.string().min(1).max(120),
      group: z.string().max(40).optional(),
      note: z.string().max(1000).optional(),
      sets: z
        .array(
          z.object({
            weight_kg: z.number().min(0).max(1000).nullable().optional(),
            reps: z.number().int().min(0).max(1000),
            done: z.boolean().optional()
          })
        )
        .min(1)
        .max(30)
    })
  )
  .max(100);

export const healthTools: ToolDefinition[] = [
  {
    name: 'meos_health_get_summary',
    title: 'Get health summary',
    description:
      'Daily health metrics MeOS tracks (weight, calories, protein, water, steps) plus derived 7/30-day averages, workout counts and the calorie/macro targets the Fitness tab computes. Averages are labelled as calculated; raw values are the ones actually logged.',
    inputSchema: {},
    scopes: ['read', 'health'],
    async handler(_args, ctx) {
      const fitness = await readObject<Record<string, FitnessDay>>(ctx, STATE_KEYS.fitness, {});
      const training = await readObject<TrainingState>(ctx, STATE_KEYS.training, DEFAULT_TRAINING);
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      const fp = await readObject<FitnessProfile>(ctx, STATE_KEYS.fitnessProfile, DEFAULT_FITNESS_PROFILE);
      const today = todayKey();

      const window = (days: number) => {
        const from = addDays(today, -days + 1);
        return Object.entries(fitness).filter(([d, v]) => d >= from && d <= today && v && typeof v === 'object');
      };
      const avg = (rows: Array<[string, FitnessDay]>, pick: (d: FitnessDay) => number | null | undefined) => {
        const values = rows.map(([, d]) => pick(d)).filter((n): n is number => typeof n === 'number');
        return values.length ? Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10 : null;
      };

      const d7 = window(7);
      const d30 = window(30);
      const weight = latestWeight(fitness);
      const workouts7 = Object.entries(training.dayLog ?? {}).filter(
        ([d, l]) => d >= addDays(today, -6) && d <= today && l?.done
      ).length;

      return ok(
        {
          today: {
            date: today,
            metrics: fitness[today] ?? null
          },
          latest_weight: weight,
          averages: {
            last_7_days: {
              calories: avg(d7, (d) => d.calories),
              protein_g: avg(d7, (d) => d.proteinG),
              water_ml: avg(d7, (d) => d.waterMl),
              steps: avg(d7, (d) => d.steps),
              days_logged: d7.length
            },
            last_30_days: {
              calories: avg(d30, (d) => d.calories),
              protein_g: avg(d30, (d) => d.proteinG),
              water_ml: avg(d30, (d) => d.waterMl),
              steps: avg(d30, (d) => d.steps),
              days_logged: d30.length
            }
          },
          workouts: { last_7_days: workouts7 },
          targets: calorieTargets(profile, fp, weight?.kg ?? null),
          bmi: bmi(profile.heightCm ?? null, weight?.kg ?? null)
        },
        { averages: 'calculated from logged days; not medical advice' }
      );
    }
  },

  {
    name: 'meos_health_list_daily_metrics',
    title: 'List daily health metrics',
    description: 'List logged daily health metrics in a date range, newest first. Omit dates for the most recent records.',
    inputSchema: {
      from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read', 'health'],
    async handler(args, ctx) {
      const fitness = await readObject<Record<string, FitnessDay>>(ctx, STATE_KEYS.fitness, {});
      const from = args.from ? assertDateKey(args.from, 'from') : null;
      const to = args.to ? assertDateKey(args.to, 'to') : null;
      if (from && to && from > to) throw errors.invalidInput('from must be on or before to');
      const rows = Object.entries(fitness)
        .filter(([d]) => (!from || d >= from) && (!to || d <= to))
        .sort(([a], [b]) => b.localeCompare(a))
        .map(([date, metrics]) => ({ date, ...metrics }));
      const page = paginate(rows, args.limit, args.cursor);
      return ok({ ...page, total_matching: rows.length });
    }
  },

  {
    name: 'meos_health_get_daily_metrics',
    title: 'Get one day of health metrics',
    description: 'Read the metrics logged for one yyyy-MM-dd date.',
    inputSchema: { date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) },
    scopes: ['read', 'health'],
    async handler(args, ctx) {
      const fitness = await readObject<Record<string, FitnessDay>>(ctx, STATE_KEYS.fitness, {});
      const date = assertDateKey(args.date);
      return ok({ date, metrics: fitness[date] ?? null });
    }
  },

  {
    name: 'meos_health_upsert_daily_metrics',
    title: 'Update daily health metrics',
    description:
      'Write health metrics for one day. Only supplied fields are changed; other fields already on that day are preserved. Values are stored exactly as given and sync to the app.',
    inputSchema: {
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      weight_kg: z.number().min(20).max(500).nullable().optional(),
      calories: z.number().min(0).max(20000).nullable().optional(),
      protein_g: z.number().min(0).max(1000).nullable().optional(),
      water_ml: z.number().min(0).max(20000).nullable().optional(),
      steps: z.number().int().min(0).max(200000).nullable().optional(),
      note: z.string().max(500).nullable().optional()
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const date = assertDateKey(args.date ?? todayKey());
      const patch: Partial<FitnessDay> = {};
      if (args.weight_kg !== undefined) patch.weightKg = args.weight_kg;
      if (args.calories !== undefined) patch.calories = args.calories;
      if (args.protein_g !== undefined) patch.proteinG = args.protein_g;
      if (args.water_ml !== undefined) patch.waterMl = args.water_ml;
      if (args.steps !== undefined) patch.steps = args.steps;
      if (args.note !== undefined) patch.note = args.note;
      if (Object.keys(patch).length === 0) throw errors.invalidInput('Nothing to update');

      let saved: FitnessDay = patch;
      await ctx.services.store.update<Record<string, FitnessDay>>(STATE_KEYS.fitness, (current) => {
        const base = current ?? {};
        saved = { ...(base[date] ?? {}), ...patch };
        return { ...base, [date]: saved };
      });
      return ok({ date, metrics: saved }, { written: STATE_KEYS.fitness });
    }
  },

  {
    name: 'meos_health_get_body_metrics',
    title: 'Get body metrics',
    description: 'Height, latest weight, BMI and 30-day weight change, plus the stored weight goal. Does not return body photos.',
    inputSchema: {},
    scopes: ['read', 'health'],
    async handler(_args, ctx) {
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      const fp = await readObject<FitnessProfile>(ctx, STATE_KEYS.fitnessProfile, DEFAULT_FITNESS_PROFILE);
      const fitness = await readObject<Record<string, FitnessDay>>(ctx, STATE_KEYS.fitness, {});
      const latest = latestWeight(fitness);
      const monthAgo = latestWeight(fitness, addDays(todayKey(), -30));
      return ok({
        height_cm: profile.heightCm ?? null,
        latest_weight: latest,
        weight_change_30d_kg: latest && monthAgo ? Math.round((latest.kg - monthAgo.kg) * 10) / 10 : null,
        bmi: bmi(profile.heightCm ?? null, latest?.kg ?? null),
        goal: {
          type: fp.goal ?? 'maintain',
          target_weight_kg: fp.targetWeightKg ?? null,
          calorie_target_kcal: fp.calorieTargetKcal ?? null,
          protein_target_g: fp.proteinTargetG ?? null
        }
      });
    }
  },

  {
    name: 'meos_fitness_get_profile',
    title: 'Get fitness profile',
    description: 'The stored training intent (cut/maintain/bulk), sex, activity level, targets, and the targets MeOS derives from the latest weight.',
    inputSchema: {},
    scopes: ['read', 'health'],
    async handler(_args, ctx) {
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      const fp = await readObject<FitnessProfile>(ctx, STATE_KEYS.fitnessProfile, DEFAULT_FITNESS_PROFILE);
      const fitness = await readObject<Record<string, FitnessDay>>(ctx, STATE_KEYS.fitness, {});
      const weight = latestWeight(fitness);
      return ok({
        stored: fp,
        height_cm: profile.heightCm ?? null,
        latest_weight_kg: weight?.kg ?? null,
        computed_targets: calorieTargets(profile, fp, weight?.kg ?? null)
      });
    }
  },

  {
    name: 'meos_fitness_get_workout_history',
    title: 'Get workout history',
    description: 'Workout days logged in MeOS, newest first, with title, completion, set count and volume. Filter by date range.',
    inputSchema: {
      from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read', 'health'],
    async handler(args, ctx) {
      const training = await readObject<TrainingState>(ctx, STATE_KEYS.training, DEFAULT_TRAINING);
      const from = args.from ? assertDateKey(args.from, 'from') : null;
      const to = args.to ? assertDateKey(args.to, 'to') : null;
      const rows = Object.entries(training.dayLog ?? {})
        .filter(([d]) => (!from || d >= from) && (!to || d <= to))
        .sort(([a], [b]) => b.localeCompare(a))
        .map(([date, log]) => dayLogSummary(date, log));
      const page = paginate(rows, args.limit, args.cursor);
      return ok({ ...page, total_matching: rows.length });
    }
  },

  {
    name: 'meos_fitness_get_workout_details',
    title: 'Get a workout',
    description: 'Read the workout logged on one date: the exercises, every set, weights, reps and completion.',
    inputSchema: { date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) },
    scopes: ['read', 'health'],
    async handler(args, ctx) {
      const training = await readObject<TrainingState>(ctx, STATE_KEYS.training, DEFAULT_TRAINING);
      const date = assertDateKey(args.date);
      const log = training.dayLog?.[date];
      if (!log) throw errors.notFound(`Workout on ${date}`);
      return ok({
        ...dayLogSummary(date, log),
        entries: log.entries ?? null,
        planned_items: log.items ?? null
      });
    }
  },

  {
    name: 'meos_fitness_log_workout',
    title: 'Log a workout',
    description:
      'Record a workout on a date. Sets are stored as ExerciseLog/SetLog exactly like the app. mode="merge" (default) keeps existing entries and appends new ones; mode="replace" overwrites the day\'s entries. Other dates are never touched.',
    inputSchema: {
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      title: z.string().max(120).optional(),
      entries: EntriesShape,
      mode: z.enum(['merge', 'replace']).optional(),
      mark_done: z.boolean().optional()
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const date = assertDateKey(args.date ?? todayKey());
      const entries = parseEntries(args.entries);
      const mode = args.mode ?? 'merge';
      let saved: WorkoutDayLog | null = null;

      await ctx.services.store.update<TrainingState>(STATE_KEYS.training, (current) => {
        const base = current ?? DEFAULT_TRAINING;
        const existing = base.dayLog?.[date];
        const nextEntries = mode === 'replace' ? entries : [...(existing?.entries ?? []), ...entries];
        saved = {
          ...(existing ?? { done: false, skipped: false, restOverride: false }),
          entries: nextEntries,
          title: args.title?.trim() || existing?.title || null,
          done: args.mark_done !== false,
          skipped: false,
          restOverride: false
        };
        return { ...base, dayLog: { ...(base.dayLog ?? {}), [date]: saved } };
      });
      return ok({ date, workout: dayLogSummary(date, saved!) }, { written: STATE_KEYS.training });
    }
  },

  {
    name: 'meos_fitness_update_workout',
    title: 'Update a workout',
    description:
      'Change a workout already logged on a date. Only supplied fields change; entries are preserved unless explicitly replaced. Use mark_skipped=true to record a skipped session without deleting its history.',
    inputSchema: {
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
      title: z.string().max(120).optional(),
      entries: EntriesShape.optional(),
      mark_done: z.boolean().optional(),
      mark_skipped: z.boolean().optional()
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const date = assertDateKey(args.date);
      const training = await readObject<TrainingState>(ctx, STATE_KEYS.training, DEFAULT_TRAINING);
      if (!training.dayLog?.[date]) throw errors.notFound(`Workout on ${date}`);
      if (args.mark_done === true && args.mark_skipped === true) {
        throw errors.invalidInput('mark_done and mark_skipped cannot both be true');
      }

      let saved: WorkoutDayLog | null = null;
      await ctx.services.store.update<TrainingState>(STATE_KEYS.training, (current) => {
        const base = current ?? DEFAULT_TRAINING;
        const existing = base.dayLog?.[date];
        if (!existing) throw errors.notFound(`Workout on ${date}`);
        const next: WorkoutDayLog = { ...existing };
        if (args.title !== undefined) next.title = args.title.trim() || null;
        if (args.entries !== undefined) next.entries = parseEntries(args.entries);
        if (args.mark_done !== undefined) {
          next.done = args.mark_done;
          if (args.mark_done) next.skipped = false;
        }
        if (args.mark_skipped !== undefined) {
          next.skipped = args.mark_skipped;
          if (args.mark_skipped) next.done = false;
        }
        saved = next;
        return { ...base, dayLog: { ...(base.dayLog ?? {}), [date]: next } };
      });
      return ok({ date, workout: dayLogSummary(date, saved!) }, { written: STATE_KEYS.training });
    }
  },

  {
    name: 'meos_fitness_get_exercise_history',
    title: 'Get exercise history',
    description:
      'Every logged set for one exercise id across all workouts: dates, weights, reps, top weight and estimated volume. Seed exercise names are not synced to the server, so the id is authoritative.',
    inputSchema: {
      exercise_id: z.string().min(1).max(120),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read', 'health'],
    async handler(args, ctx) {
      const training = await readObject<TrainingState>(ctx, STATE_KEYS.training, DEFAULT_TRAINING);
      const exerciseId = args.exercise_id.trim();
      const rows = Object.entries(training.dayLog ?? {})
        .map(([date, log]) => {
          const entries = (log.entries ?? []).filter((e) => e.exerciseId === exerciseId);
          if (!entries.length) return null;
          const sets = entries.flatMap((e) => e.sets ?? []);
          const done = sets.filter((s) => s.done);
          return {
            date,
            workout_title: log.title ?? null,
            sets: sets.map((s) => ({ weight_kg: s.weightKg ?? null, reps: s.reps, done: s.done })),
            top_weight_kg: done.reduce<number | null>((m, s) => (s.weightKg != null ? Math.max(m ?? 0, s.weightKg) : m), null),
            volume_kg: Math.round(done.reduce((v, s) => v + (s.weightKg ?? 0) * s.reps, 0) * 10) / 10
          };
        })
        .filter((x): x is NonNullable<typeof x> => x != null)
        .sort((a, b) => b.date.localeCompare(a.date));

      const page = paginate(rows, args.limit, args.cursor);
      return ok({
        exercise_id: exerciseId,
        ...page,
        total_matching: rows.length,
        personal_best_weight_kg: rows.reduce<number | null>(
          (m, r) => (r.top_weight_kg != null ? Math.max(m ?? 0, r.top_weight_kg) : m),
          null
        )
      });
    }
  },

  {
    name: 'meos_fitness_get_progress',
    title: 'Get fitness progress',
    description:
      'Progress picture: weight trend over 30/90 days, weekly workout consistency, total volume in the last 28 days, and current targets. Calculated values are labelled.',
    inputSchema: {},
    scopes: ['read', 'health'],
    async handler(_args, ctx) {
      const training = await readObject<TrainingState>(ctx, STATE_KEYS.training, DEFAULT_TRAINING);
      const fitness = await readObject<Record<string, FitnessDay>>(ctx, STATE_KEYS.fitness, {});
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      const fp = await readObject<FitnessProfile>(ctx, STATE_KEYS.fitnessProfile, DEFAULT_FITNESS_PROFILE);
      const today = todayKey();
      const latest = latestWeight(fitness);
      const at = (days: number) => latestWeight(fitness, addDays(today, -days))?.kg ?? null;
      const start = addDays(today, -27);
      const recent = Object.entries(training.dayLog ?? {}).filter(([d]) => d >= start && d <= today);

      const weekly = [0, 1, 2, 3].map((i) => {
        const to = addDays(today, -i * 7);
        const from = addDays(to, -6);
        const rows = Object.entries(training.dayLog ?? {}).filter(([d, l]) => d >= from && d <= to);
        return {
          week_start: from,
          week_end: to,
          done: rows.filter(([, l]) => l.done).length,
          skipped: rows.filter(([, l]) => l.skipped && !l.done).length
        };
      });

      return ok({
        weight: {
          latest,
          change_30d_kg: latest && at(30) != null ? Math.round((latest.kg - at(30)!) * 10) / 10 : null,
          change_90d_kg: latest && at(90) != null ? Math.round((latest.kg - at(90)!) * 10) / 10 : null
        },
        workouts: {
          last_28_days: {
            done: recent.filter(([, l]) => l.done).length,
            skipped: recent.filter(([, l]) => l.skipped && !l.done).length,
            volume_kg: Math.round(recent.reduce((v, [, l]) => v + sessionVolume(l.entries), 0) * 10) / 10
          },
          weekly
        },
        targets: calorieTargets(profile, fp, latest?.kg ?? null)
      });
    }
  },

  {
    name: 'meos_fitness_list_body_photos',
    title: 'List body photo metadata',
    description:
      'List progress photo ids, dates and sizes. The image bytes are end-to-end encrypted with the MeOS vault and are never returned, decrypted, or turned into a public URL. Requires the secret scope in addition to health.',
    inputSchema: {
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read', 'health', 'secret'],
    async handler(args, ctx) {
      const photos = await ctx.services.api.listBodyPhotos();
      const rows = photos
        .map((p) => ({
          id: p.id,
          date: p.date,
          bytes: p.bytes ?? null,
          updated_at: p.updatedAt ?? null,
          encrypted: true
        }))
        .sort((a, b) => b.date.localeCompare(a.date));
      const page = paginate(rows, args.limit, args.cursor);
      return ok(
        {
          ...page,
          total_matching: rows.length,
          total_bytes: photos.reduce((n, p) => n + (p.bytes ?? 0), 0)
        },
        { privacy: 'Ciphertext only. No signed URL, no decrypted image, no thumbnail is returned.' }
      );
    }
  },

  {
    name: 'meos_fitness_get_goals',
    title: 'Get fitness goals',
    description: 'The stored fitness goal and targets, and the targets derived from the latest body metrics.',
    inputSchema: {},
    scopes: ['read', 'health'],
    async handler(_args, ctx) {
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      const fp = await readObject<FitnessProfile>(ctx, STATE_KEYS.fitnessProfile, DEFAULT_FITNESS_PROFILE);
      const fitness = await readObject<Record<string, FitnessDay>>(ctx, STATE_KEYS.fitness, {});
      return ok({ goal: fp.goal ?? 'maintain', stored: fp, computed: calorieTargets(profile, fp, latestWeight(fitness)?.kg ?? null) });
    }
  },

  {
    name: 'meos_fitness_list_exercises',
    title: 'List custom exercises',
    description:
      'List exercises the owner created in MeOS. The built-in exercise library ships inside the app and is not synced, so only custom exercises appear here.',
    inputSchema: {
      query: z.string().max(120).optional(),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read', 'health'],
    async handler(args, ctx) {
      const training = await readObject<TrainingState>(ctx, STATE_KEYS.training, DEFAULT_TRAINING);
      const q = String(args.query ?? '').toLowerCase();
      const rows = (training.customExercises ?? []).filter(
        (e) => !q || e.name.toLowerCase().includes(q) || e.category.toLowerCase().includes(q)
      );
      const page = paginate(rows, args.limit, args.cursor);
      return ok({ ...page, total_matching: rows.length, built_in_library: 'not synced' });
    }
  },

  {
    name: 'meos_fitness_get_program',
    title: 'Get training program',
    description: 'Read the active training program and its days, muscle groups and planned exercises.',
    inputSchema: {},
    scopes: ['read', 'health'],
    async handler(_args, ctx) {
      const training = await readObject<TrainingState>(ctx, STATE_KEYS.training, DEFAULT_TRAINING);
      const active = (training.programs ?? []).find((p) => p.id === training.activeProgramId) ?? null;
      return ok({ active_program_id: training.activeProgramId ?? null, program: active, program_count: (training.programs ?? []).length });
    }
  }
];
