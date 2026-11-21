import type { ToolDefinition } from './registry.ts';
import { financeTools } from './finance.ts';
import { healthTools } from './health.ts';
import { taskTools } from './tasks.ts';
import { goalTools } from './goals.ts';
import { noteTools } from './notes.ts';
import { eventTools } from './events.ts';
import { memoryTools } from './memory.ts';
import { systemTools } from './system.ts';
import { dietTools } from './diet.ts';
import { knowledgeTools } from './knowledge.ts';

/**
 * One flat registry. Every tool is namespaced `meos_<module>_<action>` so a
 * multi-server agent can attribute a call without inspecting the transport.
 */
export const allTools: ToolDefinition[] = [
  ...financeTools,
  ...healthTools,
  ...taskTools,
  ...goalTools,
  ...noteTools,
  ...eventTools,
  ...memoryTools,
  ...systemTools,
  ...dietTools,
  ...knowledgeTools
];

export function findTool(name: string): ToolDefinition {
  const tool = allTools.find((t) => t.name === name);
  if (!tool) throw new Error(`Unknown MeOS tool "${name}"`);
  return tool;
}
