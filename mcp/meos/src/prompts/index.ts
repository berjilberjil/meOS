import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';

const GUARDRAILS = [
  'Use the MeOS tools to retrieve data. Do not invent personal facts, balances, dates, or records.',
  'Cite the date or period each figure covers. If a tool says a value is unavailable or stale, say so plainly.',
  'Never expose locked-note content, profile private details, tokens, keys, or health notes unless the tools returned them to you.',
  'Distinguish stored values from calculated ones (averages, recurrence projections, ROI maths) when you report them.'
].join('\n');

function prompt(text: string) {
  return {
    messages: [
      {
        role: 'user' as const,
        content: { type: 'text' as const, text: `${text}\n\nGuardrails:\n${GUARDRAILS}` }
      }
    ]
  };
}

export function registerPrompts(server: McpServer): void {
  server.registerPrompt(
    'meos_daily_briefing',
    {
      title: 'Daily briefing',
      description: 'A grounded briefing for today across tasks, events, health, diet and money.',
      argsSchema: {
        date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe('Defaults to today.')
      }
    },
    ({ date }) =>
      prompt(
        [
          `Prepare a concise daily briefing for ${date ?? 'today'} using MeOS.`,
          '',
          '1. Call meos_tasks_list with status="open" for the date, and meos_tasks_summary for the date.',
          '2. Call meos_events_get_upcoming with days=7 and mention only occurrences on or after the date.',
          '3. Call meos_health_get_summary and meos_diet_get_context; report what was actually logged versus targets.',
          '4. Call meos_finance_get_summary; if Fold is not linked or the snapshot is stale, say that instead of estimating.',
          '5. Finish with three concrete priorities. Do not repeat raw JSON.'
        ].join('\n')
      )
  );

  server.registerPrompt(
    'meos_financial_review',
    {
      title: 'Financial review',
      description: 'Review the Fold snapshot and the Stuff ledger without inventing a transaction history.',
      argsSchema: {
        month: z.string().regex(/^\d{4}-\d{2}$/).optional().describe('Month to frame the review (YYYY-MM).')
      }
    },
    ({ month }) =>
      prompt(
        [
          `Run a financial review${month ? ` for ${month}` : ''} using MeOS.`,
          '',
          'Call meos_finance_get_summary, meos_finance_list_accounts, meos_finance_get_net_worth, meos_finance_get_investments and meos_finance_get_spending.',
          'Use only those numbers. MeOS has no transaction ledger: never derive spend by adding transactions, and never infer missing balances.',
          'Separate (a) Fold-reported balances, (b) Fold-reported category spend, and (c) the Stuff ledger\'s ownership burn — they measure different things.',
          'Flag a stale Fold snapshot explicitly. Suggest at most three actions, each tied to a number you actually retrieved.'
        ].join('\n')
      )
  );

  server.registerPrompt(
    'meos_monthly_review',
    {
      title: 'Monthly review',
      description: 'A month-in-review across goals, tasks, money, training, notes and events.',
      argsSchema: {
        month: z.string().regex(/^\d{4}-\d{2}$/).optional()
      }
    },
    ({ month }) =>
      prompt(
        [
          `Write a monthly review${month ? ` for ${month}` : ' for the last 30 days'} from MeOS data.`,
          '',
          'Gather: meos_goals_list; meos_tasks_list for the month; meos_events_list for the month; meos_fitness_get_progress; meos_finance_get_summary; meos_notes_list sorted by recency; meos_memory_list (limit 20).',
          'Structure it as: what moved, what stalled, what the numbers actually say, and what to change next month.',
          'Do not claim a goal was completed unless an achievement or a done task/event supports it.'
        ].join('\n')
      )
  );

  server.registerPrompt(
    'meos_fitness_review',
    {
      title: 'Fitness review',
      description: 'Training and body-composition review from logged sets and daily metrics.',
      argsSchema: {
        days: z.number().int().min(7).max(180).optional().describe('Review window (default 28 days).')
      }
    },
    ({ days }) =>
      prompt(
        [
          `Review training and body metrics for the last ${days ?? 28} days using MeOS.`,
          '',
          'Call meos_fitness_get_progress, meos_fitness_get_workout_history, meos_fitness_get_body_metrics, meos_fitness_get_profile and meos_diet_get_context.',
          'Use logged sets and weights only. If an exercise id has no resolvable name, say "exercise <id>" rather than guessing the movement.',
          'Separate measured facts (weight readings, completed sets, volume) from calculated targets (Mifflin-St Jeor). Do not give medical advice.',
          'Note skipped sessions without shaming; suggest one adjustment for the next week.'
        ].join('\n')
      )
  );

  server.registerPrompt(
    'meos_weekly_planning',
    {
      title: 'Weekly planning',
      description: 'Plan the next week around real events, open tasks, goals and habits.',
      argsSchema: {
        week_start: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
      }
    },
    ({ week_start }) =>
      prompt(
        [
          `Plan the week${week_start ? ` starting ${week_start}` : ''} using MeOS.`,
          '',
          '1. meos_events_get_upcoming with days=14.',
          '2. meos_tasks_list with status="open" for the relevant days and meos_tasks_list_habits.',
          '3. meos_goals_list and meos_fitness_get_program.',
          '4. Propose a day-by-day plan that fits the real events and open tasks. Create tasks only if the user asks you to.',
          'Do not schedule over all-day events or assume free time you did not verify.'
        ].join('\n')
      )
  );

  server.registerPrompt(
    'meos_goal_progress_review',
    {
      title: 'Goal progress review',
      description: 'Assess life and fitness goals against actual tasks, events and training.',
      argsSchema: {
        horizon: z.enum(['short', 'mid', 'long', 'all']).optional()
      }
    },
    ({ horizon }) =>
      prompt(
        [
          `Review progress on ${horizon && horizon !== 'all' ? `${horizon}-term` : 'all'} goals in MeOS.`,
          '',
          'Call meos_goals_list, meos_tasks_list (last 30 days), meos_events_list (last 30 days) and, for fitness goals, meos_fitness_get_progress.',
          'For each goal, state the evidence for or against progress. If there is no evidence, say "no evidence logged" — never manufacture a percentage.',
          'Recommend at most one concrete next action per goal. Do not archive or edit a goal unless the user explicitly asks.'
        ].join('\n')
      )
  );
}
