<script lang="ts">
	let { size = 64, dim = false }: { size?: number; dim?: boolean } = $props();
	const id = `fg-${Math.round(size)}-${dim ? 'd' : 'l'}`;
</script>

<svg
	width={size}
	height={size * 1.18}
	viewBox="0 0 100 118"
	role="img"
	aria-label="streak flame"
	style={dim ? 'opacity:.35;filter:grayscale(.6)' : ''}
>
	<defs>
		<linearGradient id={`${id}-in`} x1="0" y1="0" x2="0" y2="1">
			<stop offset="0" stop-color="#ff5b2e" />
			<stop offset="1" stop-color="#ff9a00" />
		</linearGradient>
	</defs>
	<ellipse cx="50" cy="108" rx="24" ry="6" fill="#7a7400" opacity="0.5" />
	<path
		d="M50 4 C 70 28, 92 44, 80 76 C 74 98, 60 110, 50 110 C 40 110, 26 98, 20 76 C 8 44, 30 28, 50 4 Z"
		fill="#ffc800"
	/>
	<path
		d="M53 28 C 67 46, 78 56, 70 78 C 65 94, 56 102, 50 102 C 44 102, 36 92, 33 80 C 28 60, 41 48, 53 28 Z"
		fill={`url(#${id}-in)`}
	/>
	<circle cx="50" cy="80" r="13" fill="#fff" />
</svg>
