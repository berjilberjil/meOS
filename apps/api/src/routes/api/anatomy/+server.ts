import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
  bodyFront, bodyBack, frontOutline, backOutline, FRONT_VIEWBOX, BACK_VIEWBOX
} from '$lib/data/body-paths';
import { muscleGroups } from '$lib/data/anatomy';
import { muscleActivation } from '$lib/data/muscle-activation';

// Public, read-only anatomy data for native clients (apps/ios): the SVG body
// maps, muscle groups, and per-group activation rankings — same source the web
// bundle uses. Cached hard at the edge; changes only on deploy.
export const GET: RequestHandler = () => {
  return json(
    {
      front: { viewBox: FRONT_VIEWBOX, outline: frontOutline, muscles: bodyFront },
      back: { viewBox: BACK_VIEWBOX, outline: backOutline, muscles: bodyBack },
      groups: muscleGroups,
      activation: muscleActivation
    },
    { headers: { 'cache-control': 'public, max-age=3600' } }
  );
};
