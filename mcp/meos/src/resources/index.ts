import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { findTool } from '../tools/index.ts';
import { runTool, type ToolContext } from '../tools/registry.ts';
import { todayKey } from '../utils/dates.ts';

interface ResourceSpec {
  name: string;
  uri: string;
  title: string;
  description: string;
  tool: string;
  args?: Record<string, unknown>;
}

/**
 * Resources are deliberately thin wrappers over the same tools. That keeps one
 * permission check, one error envelope and one data path — a resource can never
 * return something its matching tool would refuse.
 */
const RESOURCES: ResourceSpec[] = [
  {
    name: 'profile',
    uri: 'meos://profile',
    title: 'MeOS profile',
    description: 'Identity, work, links, goals by horizon, achievements and habits.',
    tool: 'meos_get_profile'
  },
  {
    name: 'finance-summary',
    uri: 'meos://finance/summary',
    title: 'Finance summary',
    description: 'Fold net worth, cash, investments, debt and this month\'s spend, plus ownership burn.',
    tool: 'meos_finance_get_summary'
  },
  {
    name: 'finance-accounts',
    uri: 'meos://finance/accounts',
    title: 'Finance accounts',
    description: 'Linked bank accounts with masked last four digits and balances.',
    tool: 'meos_finance_list_accounts'
  },
  {
    name: 'health-summary',
    uri: 'meos://health/summary',
    title: 'Health summary',
    description: 'Latest metrics, 7/30-day averages, workouts and calorie targets.',
    tool: 'meos_health_get_summary'
  },
  {
    name: 'fitness-progress',
    uri: 'meos://fitness/progress',
    title: 'Fitness progress',
    description: 'Weight trend, weekly consistency and recent training volume.',
    tool: 'meos_fitness_get_progress'
  },
  {
    name: 'tasks-active',
    uri: 'meos://tasks/active',
    title: 'Today\'s open tasks',
    description: 'The current day\'s unfinished to-dos.',
    tool: 'meos_tasks_list',
    args: { status: 'open' }
  },
  {
    name: 'goals',
    uri: 'meos://goals',
    title: 'Goals',
    description: 'Life goals by horizon, achievements and the fitness goal.',
    tool: 'meos_goals_list'
  },
  {
    name: 'events-upcoming',
    uri: 'meos://events/upcoming',
    title: 'Upcoming events',
    description: 'Projected occurrences in the next 30 days, including recurring events.',
    tool: 'meos_events_get_upcoming',
    args: { days: 30, limit: 50 }
  },
  {
    name: 'notes-recent',
    uri: 'meos://notes/recent',
    title: 'Recent notes',
    description: 'The 20 most recently edited notes. Locked bodies stay redacted without the secret scope.',
    tool: 'meos_notes_list',
    args: { limit: 20 }
  },
  {
    name: 'memory-recent',
    uri: 'meos://memory/recent',
    title: 'Recent memories',
    description: 'The 20 most important/pinned durable facts MeOS remembers.',
    tool: 'meos_memory_list',
    args: { limit: 20 }
  },
  {
    name: 'devices',
    uri: 'meos://devices',
    title: 'Devices',
    description: 'Devices signed into this MeOS account.',
    tool: 'meos_list_devices'
  },
  {
    name: 'capabilities',
    uri: 'meos://capabilities',
    title: 'Capability inventory',
    description: 'What this MeOS build genuinely supports, and what it does not.',
    tool: 'meos_get_capabilities'
  }
];

export function registerResources(server: McpServer, ctx: ToolContext): void {
  for (const spec of RESOURCES) {
    server.registerResource(
      spec.name,
      spec.uri,
      { title: spec.title, description: spec.description, mimeType: 'application/json' },
      async (uri) => {
        const def = findTool(spec.tool);
        const args = { ...(spec.args ?? {}) };
        if (spec.uri === 'meos://tasks/active' && !args.from) {
          args.from = todayKey();
          args.to = todayKey();
        }
        const result = await runTool(def, args, ctx);
        const structured = result.structuredContent as Record<string, unknown> | undefined;
        if (result.isError) {
          const error = (structured?.error as { message?: string } | undefined)?.message ?? 'Resource unavailable';
          throw new Error(error);
        }
        return {
          contents: [
            {
              uri: uri.href,
              mimeType: 'application/json',
              text: JSON.stringify(structured ?? {}, null, 2)
            }
          ]
        };
      }
    );
  }
}
