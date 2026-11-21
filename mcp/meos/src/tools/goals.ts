import { z } from 'zod';
import {
  STATE_KEYS,
  DEFAULT_FITNESS_PROFILE,
  DEFAULT_PROFILE,
  type FitnessProfile,
  type Milestone,
  type Profile
} from '../schemas/models.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { nowStamp } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import type { ToolDefinition } from './registry.ts';
import { cleanText, readObject } from './shared.ts';

type Horizon = 'short' | 'mid' | 'long';
const HORIZONS: Horizon[] = ['short', 'mid', 'long'];
const FIELD: Record<Horizon, 'goalsShort' | 'goalsMid' | 'goalsLong'> = {
  short: 'goalsShort',
  mid: 'goalsMid',
  long: 'goalsLong'
};

function parseRef(ref: string): { horizon: Horizon; index: number } {
  const m = /^(short|mid|long):(\d+)$/.exec(ref.trim());
  if (!m) throw errors.invalidInput('goal_ref must look like "short:0", "mid:1" or "long:2"');
  const horizon = m[1] as Horizon;
  const index = Number(m[2]);
  if (!Number.isInteger(index) || index < 0) throw errors.invalidInput('goal_ref index is invalid');
  return { horizon, index };
}

function readGoal(profile: Profile, ref: string): { horizon: Horizon; index: number; text: string } {
  const { horizon, index } = parseRef(ref);
  const list = profile[FIELD[horizon]] ?? [];
  if (index >= list.length) throw errors.notFound(`Goal ${ref}`);
  return { horizon, index, text: list[index]! };
}

function goalsOutput(profile: Profile) {
  const rows = HORIZONS.flatMap((horizon) =>
    (profile[FIELD[horizon]] ?? []).map((text, index) => ({
      goal_ref: `${horizon}:${index}`,
      horizon,
      index,
      text
    }))
  );
  return {
    goals: rows,
    achievements: profile.achievements ?? [],
    fitness_goal: null as null | Record<string, unknown>
  };
}

export const goalTools: ToolDefinition[] = [
  {
    name: 'meos_goals_list',
    title: 'List goals',
    description:
      'List life goals by horizon (short, mid, long) with stable goal_ref values, plus archived achievements and the fitness goal. MeOS life goals are short strings, not rich goal records.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      const fp = await readObject<FitnessProfile>(ctx, STATE_KEYS.fitnessProfile, DEFAULT_FITNESS_PROFILE);
      const out = goalsOutput(profile);
      out.fitness_goal = {
        type: fp.goal ?? 'maintain',
        target_weight_kg: fp.targetWeightKg ?? null,
        calorie_target_kcal: fp.calorieTargetKcal ?? null,
        protein_target_g: fp.proteinTargetG ?? null
      };
      return ok(out);
    }
  },

  {
    name: 'meos_goals_get',
    title: 'Get a goal',
    description: 'Read one life goal by its goal_ref (e.g. "short:0").',
    inputSchema: { goal_ref: z.string().min(1) },
    scopes: ['read'],
    async handler(args, ctx) {
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      return ok(readGoal(profile, args.goal_ref));
    }
  },

  {
    name: 'meos_goals_create',
    title: 'Create a goal',
    description: 'Add a life goal to one horizon. This writes the synced profile, so it appears in the app immediately.',
    inputSchema: {
      horizon: z.enum(['short', 'mid', 'long']),
      text: z.string().min(1).max(500)
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const horizon = args.horizon as Horizon;
      const text = cleanText(args.text, 'text', 500);
      let ref = '';
      await ctx.services.store.update<Profile>(STATE_KEYS.profile, (current) => {
        const base = current ?? DEFAULT_PROFILE;
        const list = [...(base[FIELD[horizon]] ?? []), text];
        ref = `${horizon}:${list.length - 1}`;
        return { ...base, [FIELD[horizon]]: list };
      });
      return ok({ goal_ref: ref, horizon, text }, { written: STATE_KEYS.profile });
    }
  },

  {
    name: 'meos_goals_update',
    title: 'Update a goal',
    description: 'Replace the text of one life goal by goal_ref. The horizon does not change; create in the new horizon and archive the old one instead.',
    inputSchema: {
      goal_ref: z.string().min(1),
      text: z.string().min(1).max(500)
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const text = cleanText(args.text, 'text', 500);
      const { horizon, index } = parseRef(args.goal_ref);
      await ctx.services.store.update<Profile>(STATE_KEYS.profile, (current) => {
        const base = current ?? DEFAULT_PROFILE;
        const list = [...(base[FIELD[horizon]] ?? [])];
        if (index >= list.length) throw errors.notFound(`Goal ${args.goal_ref}`);
        list[index] = text;
        return { ...base, [FIELD[horizon]]: list };
      });
      return ok({ goal_ref: args.goal_ref, horizon, text }, { written: STATE_KEYS.profile });
    }
  },

  {
    name: 'meos_goals_archive',
    title: 'Archive a goal',
    description:
      'Move a life goal into the profile\'s achievements timeline with the current year, then remove it from its horizon. This is how MeOS records a finished goal; nothing is deleted.',
    inputSchema: { goal_ref: z.string().min(1), note: z.string().max(500).optional() },
    scopes: ['write'],
    async handler(args, ctx) {
      const { horizon, index } = parseRef(args.goal_ref);
      const year = String(new Date().getFullYear());
      let milestone: Milestone | null = null;
      await ctx.services.store.update<Profile>(STATE_KEYS.profile, (current) => {
        const base = current ?? DEFAULT_PROFILE;
        const list = [...(base[FIELD[horizon]] ?? [])];
        if (index >= list.length) throw errors.notFound(`Goal ${args.goal_ref}`);
        const [text] = list.splice(index, 1);
        milestone = {
          id: newId(),
          year,
          title: text!,
          note: args.note?.trim() || `Archived from ${horizon}-term goals`
        };
        return {
          ...base,
          [FIELD[horizon]]: list,
          achievements: [...(base.achievements ?? []), milestone]
        };
      });
      return ok({ archived: true, goal_ref: args.goal_ref, achievement: milestone }, { written: STATE_KEYS.profile });
    }
  },

  {
    name: 'meos_goals_set_fitness',
    title: 'Set fitness goal',
    description:
      'Update the fitness intent stored on the fitness profile: cut/maintain/bulk, target weight, calorie and protein targets. Requires health scope because it changes training data.',
    inputSchema: {
      goal: z.enum(['cut', 'maintain', 'bulk']).optional(),
      target_weight_kg: z.number().min(20).max(500).nullable().optional(),
      calorie_target_kcal: z.number().min(500).max(20000).nullable().optional(),
      protein_target_g: z.number().min(0).max(1000).nullable().optional()
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const patch: Partial<FitnessProfile> = {};
      if (args.goal !== undefined) patch.goal = args.goal;
      if (args.target_weight_kg !== undefined) patch.targetWeightKg = args.target_weight_kg;
      if (args.calorie_target_kcal !== undefined) patch.calorieTargetKcal = args.calorie_target_kcal;
      if (args.protein_target_g !== undefined) patch.proteinTargetG = args.protein_target_g;
      if (Object.keys(patch).length === 0) throw errors.invalidInput('Nothing to update');

      let saved: FitnessProfile = DEFAULT_FITNESS_PROFILE;
      await ctx.services.store.update<FitnessProfile>(STATE_KEYS.fitnessProfile, (current) => {
        saved = { ...(current ?? DEFAULT_FITNESS_PROFILE), ...patch };
        return saved;
      });
      return ok({ fitness_profile: saved, updated_at: nowStamp() }, { written: STATE_KEYS.fitnessProfile });
    }
  }
];
