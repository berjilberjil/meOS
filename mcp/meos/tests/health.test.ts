import test from 'node:test';
import assert from 'node:assert/strict';
import { createHarness, errorCode, payload } from './support/harness.ts';
import { todayKey } from '../src/utils/dates.ts';

test('health summary reports latest metrics, calculated averages and targets', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'health']);
    const result = await h.call(ctx, 'meos_health_get_summary', {});
    const data = payload(result).data;
    assert.equal(data.today.metrics.weightKg, 74);
    assert.equal(data.latest_weight.kg, 74);
    assert.equal(data.averages.last_7_days.calories, 2100);
    assert.equal(data.averages.last_7_days.days_logged, 1);
    assert.equal(data.workouts.last_7_days, 1);
    assert.equal(data.bmi.value, 23.4);
    assert.equal(data.targets.goal_calories, 2147);
    assert.equal(data.targets.protein_g, 148);
    assert.match(payload(result).metadata.averages, /calculated/);
  } finally {
    await h.close();
  }
});

test('daily metric upsert preserves fields it was not given', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const result = await h.call(ctx, 'meos_health_upsert_daily_metrics', {
      date: todayKey(),
      steps: 12000
    });
    const metrics = payload(result).data.metrics;
    assert.equal(metrics.steps, 12000);
    assert.equal(metrics.weightKg, 74);
    assert.equal(metrics.note, 'good day');
    assert.deepEqual(metrics.hailed, [1]);
  } finally {
    await h.close();
  }
});

test('daily metric validation rejects impossible values', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const result = await h.call(ctx, 'meos_health_upsert_daily_metrics', { weight_kg: 5 });
    assert.equal(result.isError, true);
  } finally {
    await h.close();
  }
});

test('workout history and details reflect logged sets', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'health']);
    const history = payload(await h.call(ctx, 'meos_fitness_get_workout_history', {})).data;
    assert.equal(history.items[0].date, todayKey());
    assert.equal(history.items[0].volume_kg, 1140);
    assert.equal(history.items[0].completed_sets, 3);
    assert.equal(history.items[0].title, 'Push A');

    const detail = payload(await h.call(ctx, 'meos_fitness_get_workout_details', { date: todayKey() })).data;
    assert.equal(detail.entries.length, 2);
    assert.equal(detail.entries[0].sets[0].weightKg, 60);
  } finally {
    await h.close();
  }
});

test('logging a workout merges by default and replaces on request', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const merged = payload(
      await h.call(ctx, 'meos_fitness_log_workout', {
        date: todayKey(),
        entries: [{ exercise_id: 'ex-custom', sets: [{ weight_kg: 65, reps: 5 }] }]
      })
    ).data;
    assert.equal(merged.workout.completed_sets, 4);

    const replaced = payload(
      await h.call(ctx, 'meos_fitness_log_workout', {
        date: todayKey(),
        mode: 'replace',
        entries: [{ exercise_id: 'ex-custom', sets: [{ weight_kg: 70, reps: 3, done: true }] }]
      })
    ).data;
    assert.equal(replaced.workout.completed_sets, 1);
    assert.equal(replaced.workout.volume_kg, 210);
  } finally {
    await h.close();
  }
});

test('updating a workout requires an existing day and preserves entries unless replaced', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const missing = await h.call(ctx, 'meos_fitness_update_workout', { date: '2030-01-01', title: 'X' });
    assert.equal(errorCode(missing), 'not_found');

    const updated = payload(await h.call(ctx, 'meos_fitness_update_workout', { date: todayKey(), title: 'Push B' })).data;
    assert.equal(updated.workout.title, 'Push B');
    assert.equal(updated.workout.completed_sets, 3);
  } finally {
    await h.close();
  }
});

test('exercise history aggregates sets and finds a personal best', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'health']);
    const data = payload(await h.call(ctx, 'meos_fitness_get_exercise_history', { exercise_id: 'ex-custom' })).data;
    assert.equal(data.total_matching, 1);
    assert.equal(data.items[0].top_weight_kg, 60);
    assert.equal(data.items[0].volume_kg, 900);
    assert.equal(data.personal_best_weight_kg, 60);
  } finally {
    await h.close();
  }
});

test('body photo metadata needs the secret scope and never returns a URL', async () => {
  const h = await createHarness();
  try {
    const denied = await h.call(h.ctxFor('a', ['read', 'health']), 'meos_fitness_list_body_photos', {});
    assert.equal(errorCode(denied), 'forbidden');

    const result = await h.call(h.ctxFor('a', ['read', 'health', 'secret']), 'meos_fitness_list_body_photos', {});
    const data = payload(result).data;
    assert.equal(data.total_matching, 2);
    assert.equal(data.total_bytes, 3000);
    const serialized = JSON.stringify(data);
    assert.equal(serialized.includes('signed.example'), false);
    assert.equal(serialized.includes('url'), false);
    assert.equal(data.items[0].id, '2026-02-01__p2');
  } finally {
    await h.close();
  }
});

test('custom exercises and the active program are readable', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'health']);
    const exercises = payload(await h.call(ctx, 'meos_fitness_list_exercises', { query: 'cable' })).data;
    assert.equal(exercises.items.length, 1);
    assert.equal(exercises.built_in_library, 'not synced');

    const program = payload(await h.call(ctx, 'meos_fitness_get_program', {})).data;
    assert.equal(program.program.name, 'PPL');
    assert.equal(program.program_count, 1);
  } finally {
    await h.close();
  }
});

test('progress reports weight change, weekly consistency and volume', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('a', ['read', 'health']), 'meos_fitness_get_progress', {})).data;
    assert.equal(data.weight.latest.kg, 74);
    assert.equal(data.workouts.last_28_days.done, 1);
    assert.equal(data.workouts.last_28_days.volume_kg, 1140);
    assert.equal(data.workouts.weekly.length, 4);
  } finally {
    await h.close();
  }
});
