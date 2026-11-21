import test from 'node:test';
import assert from 'node:assert/strict';
import { createHarness, errorCode, payload } from './support/harness.ts';
import { addDays, todayKey } from '../src/utils/dates.ts';

test('tasks list filters by status and preserves per-day ownership', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read']);
    const open = payload(await h.call(ctx, 'meos_tasks_list', { status: 'open' })).data;
    assert.equal(open.items.some((t: any) => t.id === 'todo-1'), true);
    assert.equal(open.items.some((t: any) => t.id === 'todo-2'), false);
    assert.equal(open.items.find((t: any) => t.id === 'todo-old').date, '2026-01-01');

    const todayOpen = payload(await h.call(ctx, 'meos_tasks_list', { status: 'open', from: todayKey(), to: todayKey() })).data;
    assert.deepEqual(todayOpen.items.map((t: any) => t.id), ['todo-1']);
  } finally {
    await h.close();
  }
});

test('tasks can be created, moved to another day, completed and restored from the bin', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'destructive']);
    const created = payload(await h.call(ctx, 'meos_tasks_create', { text: 'Write tests', mins: 40 })).data;
    assert.equal(created.text, 'Write tests');
    assert.equal(created.date, todayKey());

    const moved = payload(
      await h.call(ctx, 'meos_tasks_update', { id: created.id, date: addDays(todayKey(), 1), text: 'Write more tests' })
    ).data;
    assert.equal(moved.date, addDays(todayKey(), 1));
    assert.equal(moved.text, 'Write more tests');

    const completed = payload(await h.call(ctx, 'meos_tasks_complete', { id: created.id })).data;
    assert.equal(completed.done, true);

    const deleted = payload(await h.call(ctx, 'meos_tasks_delete', { id: created.id, confirm: true })).data;
    assert.equal(deleted.date, addDays(todayKey(), 1));

    const restored = payload(await h.call(ctx, 'meos_restore_from_trash', { entry_id: deleted.recycle_bin_entry })).data;
    assert.equal(restored.restored, true);

    const fetched = payload(await h.call(ctx, 'meos_tasks_get', { id: created.id })).data;
    assert.equal(fetched.date, addDays(todayKey(), 1));
    assert.equal(fetched.done, true);
  } finally {
    await h.close();
  }
});

test('task update rejects an empty patch and unknown ids', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    assert.equal(errorCode(await h.call(ctx, 'meos_tasks_update', { id: 'todo-1' })), 'invalid_input');
    assert.equal(errorCode(await h.call(ctx, 'meos_tasks_update', { id: 'nope', text: 'x' })), 'not_found');
  } finally {
    await h.close();
  }
});

test('habits are ticked per day and unknown names are rejected', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const list = payload(await h.call(ctx, 'meos_tasks_list_habits', {})).data;
    assert.deepEqual(list.habits, [
      { name: 'Gym', done: true },
      { name: 'Read', done: false }
    ]);

    await h.call(ctx, 'meos_tasks_set_habit', { name: 'Read', done: true });
    const after = payload(await h.call(ctx, 'meos_tasks_list_habits', {})).data;
    assert.equal(after.habits.find((x: any) => x.name === 'Read').done, true);

    const unknown = await h.call(ctx, 'meos_tasks_set_habit', { name: 'Fly', done: true });
    assert.equal(errorCode(unknown), 'invalid_input');
  } finally {
    await h.close();
  }
});

test('life goals can be created, edited and archived into achievements', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write']);
    const listed = payload(await h.call(ctx, 'meos_goals_list', {})).data;
    assert.deepEqual(listed.goals.map((g: any) => g.goal_ref), ['short:0', 'mid:0', 'long:0']);
    assert.equal(listed.fitness_goal.type, 'cut');

    const created = payload(await h.call(ctx, 'meos_goals_create', { horizon: 'short', text: 'Run a 10k' })).data;
    assert.equal(created.goal_ref, 'short:1');

    const updated = payload(await h.call(ctx, 'meos_goals_update', { goal_ref: 'short:1', text: 'Run a half marathon' })).data;
    assert.equal(updated.text, 'Run a half marathon');

    const archived = payload(
      await h.call(ctx, 'meos_goals_archive', { goal_ref: 'short:1', note: 'Completed in October' })
    ).data;
    assert.equal(archived.archived, true);
    assert.equal(archived.achievement.title, 'Run a half marathon');
    assert.equal(archived.achievement.note, 'Completed in October');

    const after = payload(await h.call(ctx, 'meos_goals_list', {})).data;
    assert.equal(after.goals.some((g: any) => g.text === 'Run a half marathon'), false);
    assert.equal(after.achievements.some((a: any) => a.title === 'Run a half marathon'), true);
  } finally {
    await h.close();
  }
});

test('fitness goal edits preserve unrelated fitness settings', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const saved = payload(await h.call(ctx, 'meos_goals_set_fitness', { goal: 'bulk', target_weight_kg: 80 })).data
      .fitness_profile;
    assert.equal(saved.goal, 'bulk');
    assert.equal(saved.targetWeightKg, 80);
    assert.equal(saved.calorieTargetKcal, 2000);
    assert.equal(saved.proteinTargetG, 160);
  } finally {
    await h.close();
  }
});
