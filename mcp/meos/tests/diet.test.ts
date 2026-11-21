import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHarness, errorCode, payload } from './support/harness.ts';
import { addDays, todayKey } from '../src/utils/dates.ts';

const foods = JSON.parse(readFileSync(new URL('../../diet/src/foods.json', import.meta.url), 'utf8')) as Array<{
  id: string;
  name: string;
  perServing: { calories: number; protein: number; carbs: number; fats: number; fiber: number };
}>;
const seed = foods[0]!;
const seedWeekday = String(
  new Date(Date.UTC(Number(todayKey().slice(0, 4)), Number(todayKey().slice(5, 7)) - 1, Number(todayKey().slice(8, 10)))).getUTCDay()
);

test('diet context reports the day plan, log and targets', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('a', ['read', 'health']), 'meos_diet_get_context', {})).data;
    assert.equal(data.date, todayKey());
    assert.equal(data.weekday, Number(seedWeekday));
    assert.equal(data.today_log.totals.energy_kcal, Math.round(seed.perServing.calories));
    assert.equal(data.today_plan.totals.energy_kcal, Math.round(seed.perServing.calories * 2));
    assert.equal(data.goals.stored.energy_kcal, 2000);
    assert.equal(data.goals.computed.protein_g, 148);
  } finally {
    await h.close();
  }
});

test('the week plan always has seven days with totals', async () => {
  const h = await createHarness();
  try {
    const data = payload(await h.call(h.ctxFor('a', ['read', 'health']), 'meos_diet_get_week_plan', {})).data;
    assert.equal(data.days.length, 7);
    const day = data.days.find((d: any) => d.weekday === Number(seedWeekday));
    assert.equal(day.meals.breakfast.length, 1);
    assert.equal(day.totals.energy_kcal, Math.round(seed.perServing.calories * 2));
  } finally {
    await h.close();
  }
});

test('food search and logging write to the log, not the plan', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const found = payload(await h.call(ctx, 'meos_diet_search_foods', { query: seed.name.slice(0, 4) })).data;
    assert.ok(found.foods.some((f: any) => f.id === seed.id));

    const before = payload(await h.call(ctx, 'meos_diet_get_day_log', { date: todayKey() })).data;
    const after = payload(
      await h.call(ctx, 'meos_diet_log_food', { food_id: seed.id, meal: 'snacks', quantity: 1 })
    ).data;
    assert.equal(after.totals.energy_kcal, before.totals.energy_kcal + Math.round(seed.perServing.calories));
    assert.equal(after.meals.snacks.length, 1);
    assert.ok(after.confirmed.includes('breakfast'), 'existing confirmations must survive a log write');
    assert.ok(after.confirmed.includes('snacks'));
  } finally {
    await h.close();
  }
});

test('a planned meal can be copied into the log exactly once', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const tomorrow = addDays(todayKey(), 1);
    await h.call(ctx, 'meos_diet_set_meal_slot', {
      date: tomorrow,
      meal: 'lunch',
      foods: [{ food_id: seed.id, quantity: 1.5 }]
    });

    const logged = payload(await h.call(ctx, 'meos_diet_log_planned_meal', { date: tomorrow, meal: 'lunch' })).data;
    assert.equal(logged.meals.lunch.length, 1);
    assert.equal(logged.meals.lunch[0].quantity, 1.5);

    const again = await h.call(ctx, 'meos_diet_log_planned_meal', { date: tomorrow, meal: 'lunch' });
    assert.equal(errorCode(again), 'conflict');
  } finally {
    await h.close();
  }
});

test('log planned refuses an empty slot instead of pretending to write', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const result = await h.call(ctx, 'meos_diet_log_planned_meal', { date: addDays(todayKey(), 2), meal: 'dinner' });
    assert.equal(errorCode(result), 'conflict');
  } finally {
    await h.close();
  }
});

test('slot editing validates food ids and replaces only that slot', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const bad = await h.call(ctx, 'meos_diet_set_meal_slot', {
      weekday: Number(seedWeekday),
      meal: 'dinner',
      foods: [{ food_id: 'made-up', quantity: 1 }]
    });
    assert.equal(errorCode(bad), 'invalid_input');

    const set = payload(
      await h.call(ctx, 'meos_diet_set_meal_slot', {
        weekday: Number(seedWeekday),
        meal: 'dinner',
        foods: [{ food_id: seed.id, quantity: 1 }]
      })
    ).data;
    assert.equal(set.items.length, 1);

    const plan = payload(await h.call(ctx, 'meos_diet_get_week_plan', {})).data;
    const day = plan.days.find((d: any) => d.weekday === Number(seedWeekday));
    assert.equal(day.meals.breakfast.length, 1);
    assert.equal(day.meals.dinner.length, 1);
  } finally {
    await h.close();
  }
});

test('clearing the week plan needs confirmation and leaves logs alone', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health', 'destructive']);
    const denied = await h.call(ctx, 'meos_diet_clear_week_plan', {});
    assert.equal(errorCode(denied), 'confirmation_required');

    const cleared = await h.call(ctx, 'meos_diet_clear_week_plan', { confirm: true });
    assert.equal(payload(cleared).data.cleared, true);

    const log = payload(await h.call(ctx, 'meos_diet_get_day_log', { date: todayKey() })).data;
    assert.equal(log.meals.breakfast.length, 1);
  } finally {
    await h.close();
  }
});

test('upserting a food preserves macros that were not supplied', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const created = payload(
      await h.call(ctx, 'meos_diet_upsert_food', {
        name: 'Protein Bar',
        energy_kcal: 210,
        protein_g: 20,
        carb_g: 22,
        fat_g: 7
      })
    ).data;
    assert.equal(created.per_serving.protein, 20);

    const updated = payload(
      await h.call(ctx, 'meos_diet_upsert_food', { name: 'Protein Bar', energy_kcal: 220 })
    ).data;
    assert.equal(updated.per_serving.calories, 220);
    assert.equal(updated.per_serving.protein, 20);
    assert.equal(updated.per_serving.carbs, 22);
    assert.equal(updated.per_serving.fats, 7);
  } finally {
    await h.close();
  }
});

test('diet goals change only the stored targets', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health']);
    const saved = payload(await h.call(ctx, 'meos_diet_set_goals', { energy_kcal: 2200 })).data.fitness_profile;
    assert.equal(saved.calorieTargetKcal, 2200);
    assert.equal(saved.proteinTargetG, 160);
    assert.equal(saved.goal, 'cut');
    assert.equal(saved.targetWeightKg, 70);
  } finally {
    await h.close();
  }
});

test('deleting a meal-log row needs confirmation', async () => {
  const h = await createHarness();
  try {
    const ctx = h.ctxFor('a', ['read', 'write', 'health', 'destructive']);
    const denied = await h.call(ctx, 'meos_diet_delete_log_item', { log_id: 'li1' });
    assert.equal(errorCode(denied), 'confirmation_required');
    const okResult = await h.call(ctx, 'meos_diet_delete_log_item', { log_id: 'li1', confirm: true });
    assert.equal(payload(okResult).data.deleted, true);

    const log = payload(await h.call(ctx, 'meos_diet_get_day_log', { date: todayKey() })).data;
    assert.equal(log.meals.breakfast.length, 0);
    assert.ok(log.confirmed.includes('breakfast'), 'a confirmed-then-emptied meal stays confirmed');
  } finally {
    await h.close();
  }
});
