import path from "path";
import fs from 'fs';
import esbuild, { PluginBuild } from "esbuild";

const production = process.argv.includes('--production');
const watch = process.argv.includes('--watch');

/**
 * @type {import('esbuild').Plugin}
 */
const esbuildProblemMatcherPlugin = {
	name: 'esbuild-problem-matcher',

	setup(build: PluginBuild) {
		build.onStart(() => {
			console.log('[watch] build started');
		});
		build.onEnd((result: { errors: { text: any; location: any; }[]; }) => {
			result.errors.forEach(({ text, location }) => {
				console.error(`✘ [ERROR] ${text}`);
				console.error(`    ${location.file}:${location.line}:${location.column}:`);
			});
			console.log('[watch] build finished');
		});
	},
};

/**
 * Copies files from the output directory to the distribution directory, excluding specified files.
 *
 * @param {string} sourceDir - The source directory to copy files from.
 * @param {string} destDir - The destination directory to copy files to.
 * @param {string[]} [excludePatterns=['.DS_Store', 'Thumbs.db', '*.log']] - An array of glob patterns for files to exclude.
 * @throws {TypeError} If excludePatterns is not an array or if any pattern is not a string.
 */
const copyFiles = (sourceDir: string, destDir: string, excludePatterns: string[] = ['.DS_Store', 'Thumbs.db', '*.log']) => {
	if (typeof sourceDir !== 'string' || typeof destDir !== 'string') {
		throw new TypeError('outDir and distDir must be strings');
	}
	if (!fs.existsSync(sourceDir)) {
		throw new Error(`Source directory ${sourceDir} does not exist`);
	}
	if (!Array.isArray(excludePatterns)) {
		throw new TypeError('excludePatterns must be an array');
	}
	fs.mkdirSync(destDir, { recursive: true });
	fs.readdirSync(sourceDir)
		.filter((file: string) => !excludePatterns.some(pattern => {
			if (typeof pattern !== 'string') {
				throw new TypeError('Each exclude pattern must be a string');
			}
			return new RegExp(`^${pattern.replace(/\*/g, '.*')}$`).test(file);
		}))
		.filter((pathPart: string) => {
			const isDir = fs.statSync(path.join(sourceDir, pathPart)).isDirectory();
			if (isDir) {
				const destDirPath = path.join(destDir, pathPart);
				fs.mkdirSync(destDirPath, { recursive: true });
			}
			return isDir ? false : true;
		})
		.forEach((file: string) => {
			const src = path.join(sourceDir, file);
			const dest = path.join(destDir, file);
			fs.copyFileSync(src, dest);
		});
};

/**
 * @type {import('esbuild').Plugin}
 */
const copyOutputPlugin = {
	name: 'copy-output',

	setup(build: PluginBuild) {
		build.onDispose(() => {
			// Output directory after build
			const outputPath = path.resolve('out');
			// Destination to copy files to
			const destination = path.resolve('dist');

			// Copy the files
			copyFiles(outputPath, destination);
			console.log(`Build output copied to: ${destination}`);
		});
	},
};

async function main() {
	const ctx = await esbuild.context({
		entryPoints: [
			'src/extension.ts',
			'src/test/extension.test.ts'
		],
		bundle: true,
		format: 'cjs',
		minify: production,
		sourcemap: !production,
		sourcesContent: false,
		platform: 'node',
		outdir: 'out',
		// tsconfig: 'tsconfig.esbuild.json', // Specify your custom tsconfig.json here
		external: ['vscode'],
		logLevel: 'silent',
		plugins: [
			copyOutputPlugin,
			/* add to the end of plugins array */
			esbuildProblemMatcherPlugin,
		]
	});

	if (watch) {
		// Hook to handle rebuild events, similar to `onRebuild`
		ctx.rebuild = async () => {
			try {
				const result = await ctx.rebuild();
				console.log('[watch] Rebuild succeeded');
				return result;
			} catch (error) {
				console.error('[watch] Rebuild failed:', error);
				throw error; // Ensure error is thrown so that the build fails properly
			}
		};
		console.log('[watch] Watching for changes...');
		await ctx.watch(); // This starts the watch mode
	} else {
		// Perform a single build
		await ctx.rebuild();
		const outputPath = path.resolve('out');
		const destination = path.resolve('dist');
		copyFiles(outputPath, destination);
		console.log('[build] Build completed');
		await ctx.dispose(); // Clean up after the build
	}
}

main().catch(e => {
	console.error(e);
	process.exit(1);
});
