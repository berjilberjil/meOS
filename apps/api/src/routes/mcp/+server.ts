import type { RequestHandler } from './$types';
import { serveMcp, preflight, noStream } from '$lib/server/mcpServer';

// Remote MCP endpoint for AI apps. Token in `Authorization: Bearer meos_…`.
export const POST: RequestHandler = ({ request }) => serveMcp(request);
export const OPTIONS: RequestHandler = () => preflight();
export const GET: RequestHandler = () => noStream();
