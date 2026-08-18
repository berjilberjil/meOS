# MyOS

[![Netlify Status](https://api.netlify.com/api/v1/badges/f8a8366c-c47f-40a0-ab5f-91022224ed0d/deploy-status)](https://app.netlify.com/projects/idyllic-naiad-5c5acd/deploys)

Personal life operating system — live at **[myos.berjiljacob.com](https://myos.berjiljacob.com)**. Auto-deploys from `master` via Netlify (badge above shows the latest deploy status; click it for full deploy logs).

Built with SvelteKit + Svelte 5, powered by [`sv`](https://github.com/sveltejs/cli).

## Creating a project

If you're seeing this, you've probably already done this step. Congrats!

```sh
# create a new project
npx sv create my-app
```

To recreate this project with the same configuration:

```sh
# recreate this project
npx sv@0.16.1 create --template minimal --types ts --no-install /private/tmp/claude-501/-Users-berjilskcript-Documents/5808e230-383b-449c-a376-0f550b5df9fe/scratchpad/myos-scaffold
```

## Developing

Once you've created a project and installed dependencies with `npm install` (or `pnpm install` or `yarn`), start a development server:

```sh
npm run dev

# or start the server and open the app in a new browser tab
npm run dev -- --open
```

## Building

To create a production version of your app:

```sh
npm run build
```

You can preview the production build with `npm run preview`.

> To deploy your app, you may need to install an [adapter](https://svelte.dev/docs/kit/adapters) for your target environment.
