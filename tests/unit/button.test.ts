import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import { Button, buttonVariants } from '$lib/components/ui/button';

describe('Button', () => {
	it('uses the luma base style (rounded-4xl)', () => {
		expect(buttonVariants({ variant: 'default' })).toContain('rounded-4xl');
	});

	it('renders a <button> with the destructive variant class', () => {
		const { getByRole } = render(Button, { props: { variant: 'destructive' } });
		expect(getByRole('button').className).toContain('destructive');
	});
});
