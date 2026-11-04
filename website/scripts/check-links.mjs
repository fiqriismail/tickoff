/// Validate every built page against Astro's project-path preview, including fragments and assets.
import { access, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { preview } from 'astro';
import { LinkChecker, LinkState } from 'linkinator';

const root = new URL('../', import.meta.url);
const output = new URL('dist/', root);
const files = await readdir(output, { recursive: true });
const pages = files.filter((path) => path.endsWith('.html'));
const styles = files.filter((path) => path.endsWith('.css'));

if (pages.length === 0) throw new Error('No built HTML pages found. Run npm run build first.');
await access(new URL('pagefind/pagefind.js', output));

const server = await preview({
	root: fileURLToPath(root),
	server: { host: '127.0.0.1', port: 0, open: false },
});

try {
	const origin = `http://127.0.0.1:${server.port}`;
	const { base } = (await import('../astro.config.mjs')).default;
	const prefix = `${base.replace(/\/$/, '')}/`;
	const result = await new LinkChecker().check({
		// Seed styles too: page-relative recursion boundaries can otherwise skip CSS contents.
		path: [...pages, ...styles].map((path) => `${origin}${prefix}${path.replace(/index\.html$/, '')}`),
		recurse: true,
		checkFragments: true,
		checkCss: true,
		linksToSkip: async (url) => new URL(url).origin !== origin,
	});

	const failures = result.links.filter((link) =>
		link.state === LinkState.BROKEN
		|| (link.state !== LinkState.SKIPPED && !new URL(link.url).pathname.startsWith(prefix)));
	for (const link of failures) {
		console.error(`${link.state}: ${link.url} (HTTP ${link.status ?? 'unavailable'}) from ${link.parent ?? 'build output'}`);
	}
	if (!result.passed || failures.length > 0) {
		throw new Error(`Website link validation failed (${failures.length} invalid links).`);
	}
	console.log(`Validated ${pages.length} pages and ${result.links.filter((link) => link.state === LinkState.OK).length} local links, fragments and assets under ${prefix}. External URLs were skipped.`);
} finally {
	await server.stop();
}
