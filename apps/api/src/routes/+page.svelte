<script lang="ts">
	// Static landing for a headless backend. Prerendering it keeps the root
	// request (which every scanner hits first) out of the worker entirely:
	// the platform serves it as a plain asset for zero CPU.
	export const prerender = true;
</script>

<!-- MeOS is a headless backend. This page only exists so the site root isn't a 404. -->
<main>
  <h1>MeOS</h1>
  <p>Personal operating system — backend API. Nothing to see here; the app is native.</p>
</main>

<style>
  main { font-family: -apple-system, system-ui, sans-serif; max-width: 32rem; margin: 20vh auto; padding: 0 1rem; color: #e5e7eb; }
  h1 { font-weight: 800; letter-spacing: -0.02em; }
  p { color: #9ca3af; }
  :global(body) { background: #0b0b0f; }
</style>
