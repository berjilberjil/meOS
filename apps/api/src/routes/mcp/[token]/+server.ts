import type { RequestHandler } from './$types';
import { serveMcp, preflight, noStream } from '$lib/server/mcpServer';

// Same endpoint with the token in the URL, for AI apps that only take a link.
// Prefer the header form: URLs end up in logs and browser history.
export const POST: RequestHandler = ({ request, params }) => serveMcp(request, params.token);
export const OPTIONS: RequestHandler = () => preflight();
export const GET: RequestHandler = () => noStream();
