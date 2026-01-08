import { render, screen } from '@testing-library/svelte';
import { expect, test, vi } from 'vitest';

import SidebarSectionHeaderFixture from './SidebarSectionHeaderFixture.svelte';

vi.mock('$app/environment', () => ({ browser: true }));

test('renders title and actions slot', () => {
	render(SidebarSectionHeaderFixture);

	expect(screen.getByText('Notes')).toBeInTheDocument();
	expect(screen.getByText('Add')).toBeInTheDocument();
});
