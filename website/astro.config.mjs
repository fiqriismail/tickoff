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
			logo: { src: '../Tickoff/Resources/Assets.xcassets/AppIcon.appiconset/icon_128.png' },
			description: 'User guides for Tickoff, a native macOS task manager with projects and daily goals.',
			disable404Route: true,
			customCss: ['./src/styles/custom.css'],
			components: {
				Header: './src/components/SiteHeader.astro',
				Footer: './src/components/SiteFooter.astro',
			},
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/fiqriismail/tickoff' }],
			sidebar: [
				{
					label: 'Guide',
					items: [
						{ label: 'Overview', slug: 'guide' },
						{ label: 'Getting started', slug: 'guide/getting-started' },
						{ label: 'Tasks', slug: 'guide/tasks' },
						{ label: 'Search and filters', slug: 'guide/search-and-filters' },
						{ label: 'Projects', slug: 'guide/projects' },
						{ label: 'Daily Goals', slug: 'guide/daily-goals' },
						{ label: 'Keyboard shortcuts', slug: 'guide/keyboard-shortcuts' },
						{ label: 'Appearance and display', slug: 'guide/appearance' },
					],
				},
				{
					label: 'Help',
					items: [
						{ label: 'Data and backups', slug: 'help/data-and-backups' },
						{ label: 'Troubleshooting', slug: 'help/troubleshooting' },
						{ label: 'FAQ', slug: 'help/faq' },
					],
				},
			],
		}),
	],
});
