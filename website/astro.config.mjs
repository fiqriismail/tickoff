// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
	site: 'https://fiqriismail.github.io',
	base: '/tickoff',
	trailingSlash: 'always',
	integrations: [
		starlight({
			title: 'Tickoff',
			description: 'User guides for Tickoff, a native macOS task manager with projects and daily goals.',
			disable404Route: true,
			customCss: ['./src/styles/custom.css'],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/fiqriismail/tickoff' }],
			sidebar: [
				{
					label: 'Guide',
					items: [
						{ label: 'Getting started', slug: 'guide/getting-started' },
					],
				},
				{
					label: 'Help',
					items: [{ label: 'Troubleshooting', slug: 'help/troubleshooting' }],
				},
			],
		}),
	],
});
