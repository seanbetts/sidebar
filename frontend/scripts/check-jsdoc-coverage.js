#!/usr/bin/env node
/**
 * JSDoc coverage analyzer for TypeScript/JavaScript files
 * Checks for JSDoc comments on exported functions, classes, and methods
 */

import { readFileSync, readdirSync, statSync } from 'fs';
import { join, relative } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SRC_DIR = join(__dirname, '..', 'src', 'lib');

// Statistics
const stats = {
	totalFiles: 0,
	filesWithIssues: 0,
	totalFunctions: 0,
	documentedFunctions: 0,
	totalClasses: 0,
	documentedClasses: 0,
	totalMethods: 0,
	documentedMethods: 0,
	fileDetails: []
};

const RESERVED_METHOD_NAMES = new Set([
	'if',
	'for',
	'while',
	'switch',
	'case',
	'default',
	'break',
	'continue',
	'return',
	'throw',
	'try',
	'catch',
	'finally',
	'do',
	'else',
	'await',
	'yield'
]);

/**
 * Check if a line has JSDoc comment above it
 */
function hasJSDocAbove(lines, lineIndex) {
	// Look backwards for JSDoc comment
	for (let i = lineIndex - 1; i >= 0; i--) {
		const line = lines[i].trim();

		// Stop if we hit code
		if (
			line &&
			!line.startsWith('*') &&
			!line.startsWith('//') &&
			line !== '/**' &&
			line !== '*/'
		) {
			return false;
		}

		// Found JSDoc start
		if (line === '/**') {
			return true;
		}
	}
	return false;
}

/**
 * Analyze a TypeScript/JavaScript file for JSDoc coverage
 */
function analyzeFile(filePath) {
	const content = readFileSync(filePath, 'utf-8');
	const lines = content.split('\n');
	const relativePath = relative(SRC_DIR, filePath);

	const fileStats = {
		path: relativePath,
		functions: { total: 0, documented: 0, missing: [] },
		classes: { total: 0, documented: 0, missing: [] },
		methods: { total: 0, documented: 0, missing: [] }
	};

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const trimmed = line.trim();

		// Skip comments and empty lines
		if (!trimmed || trimmed.startsWith('//') || trimmed.startsWith('*')) {
			continue;
		}

		// Check for exported class
		if (trimmed.match(/^export\s+(class|abstract\s+class)\s+(\w+)/)) {
			const match = trimmed.match(/^export\s+(?:abstract\s+)?class\s+(\w+)/);
			const className = match ? match[1] : 'Unknown';
			fileStats.classes.total++;
			stats.totalClasses++;

			if (hasJSDocAbove(lines, i)) {
				fileStats.classes.documented++;
				stats.documentedClasses++;
			} else {
				fileStats.classes.missing.push({ name: className, line: i + 1 });
			}
		}

		// Check for exported function (regular or async)
		if (trimmed.match(/^export\s+(async\s+)?function\s+(\w+)/)) {
			const match = trimmed.match(/^export\s+(?:async\s+)?function\s+(\w+)/);
			const funcName = match ? match[1] : 'Unknown';
			fileStats.functions.total++;
			stats.totalFunctions++;

			if (hasJSDocAbove(lines, i)) {
				fileStats.functions.documented++;
				stats.documentedFunctions++;
			} else {
				fileStats.functions.missing.push({ name: funcName, line: i + 1 });
			}
		}

		// Check for class methods (public methods in class)
		if (trimmed.match(/^(public\s+)?(async\s+)?(\w+)\s*\(/)) {
			// Make sure we're inside a class (crude check)
			const beforeContext = lines.slice(Math.max(0, i - 50), i).join('\n');
			if (beforeContext.includes('class ')) {
				const match = trimmed.match(/^(?:public\s+)?(?:async\s+)?(\w+)\s*\(/);
				const methodName = match ? match[1] : 'Unknown';

				// Skip constructors and private methods
				if (
					methodName !== 'constructor' &&
					!methodName.startsWith('_') &&
					!RESERVED_METHOD_NAMES.has(methodName)
				) {
					fileStats.methods.total++;
					stats.totalMethods++;

					if (hasJSDocAbove(lines, i)) {
						fileStats.methods.documented++;
						stats.documentedMethods++;
					} else {
						fileStats.methods.missing.push({ name: methodName, line: i + 1 });
					}
				}
			}
		}
	}

	// Only track files with actual exports
	if (fileStats.functions.total > 0 || fileStats.classes.total > 0 || fileStats.methods.total > 0) {
		stats.totalFiles++;
		if (
			fileStats.functions.missing.length > 0 ||
			fileStats.classes.missing.length > 0 ||
			fileStats.methods.missing.length > 0
		) {
			stats.filesWithIssues++;
		}
		stats.fileDetails.push(fileStats);
	}
}

/**
 * Recursively walk directory and analyze files
 */
function walkDirectory(dir) {
	const entries = readdirSync(dir);

	for (const entry of entries) {
		const fullPath = join(dir, entry);
		const stat = statSync(fullPath);

		if (stat.isDirectory()) {
			walkDirectory(fullPath);
		} else if (entry.endsWith('.ts') && !entry.endsWith('.d.ts')) {
			analyzeFile(fullPath);
		}
	}
}

/**
 * Calculate coverage percentage
 */
function calculateCoverage(documented, total) {
	if (total === 0) return 100;
	return ((documented / total) * 100).toFixed(1);
}

/**
 * Main execution
 */
function main() {
	console.log('Analyzing JSDoc coverage in src/lib/...\n');

	walkDirectory(SRC_DIR);

	// Print summary
	console.log('='.repeat(80));
	console.log('JSDoc Coverage Summary');
	console.log('='.repeat(80));
	console.log();

	const functionCoverage = calculateCoverage(stats.documentedFunctions, stats.totalFunctions);
	const classCoverage = calculateCoverage(stats.documentedClasses, stats.totalClasses);
	const methodCoverage = calculateCoverage(stats.documentedMethods, stats.totalMethods);

	const totalItems = stats.totalFunctions + stats.totalClasses + stats.totalMethods;
	const documentedItems =
		stats.documentedFunctions + stats.documentedClasses + stats.documentedMethods;
	const overallCoverage = calculateCoverage(documentedItems, totalItems);

	console.log('| Category   | Total | Documented | Coverage |');
	console.log('|------------|-------|------------|----------|');
	console.log(
		`| Functions  | ${stats.totalFunctions.toString().padStart(5)} | ${stats.documentedFunctions.toString().padStart(10)} | ${functionCoverage.padStart(7)}% |`
	);
	console.log(
		`| Classes    | ${stats.totalClasses.toString().padStart(5)} | ${stats.documentedClasses.toString().padStart(10)} | ${classCoverage.padStart(7)}% |`
	);
	console.log(
		`| Methods    | ${stats.totalMethods.toString().padStart(5)} | ${stats.documentedMethods.toString().padStart(10)} | ${methodCoverage.padStart(7)}% |`
	);
	console.log(
		`| **TOTAL**  | ${totalItems.toString().padStart(5)} | ${documentedItems.toString().padStart(10)} | ${overallCoverage.padStart(7)}% |`
	);
	console.log();

	console.log(`Files analyzed: ${stats.totalFiles}`);
	console.log(`Files with missing docs: ${stats.filesWithIssues}`);
	console.log();

	// Top offenders
	if (stats.filesWithIssues > 0) {
		console.log('='.repeat(80));
		console.log('Files with Missing Documentation (Top 10)');
		console.log('='.repeat(80));
		console.log();

		const sorted = stats.fileDetails
			.filter(
				(f) => f.functions.missing.length + f.classes.missing.length + f.methods.missing.length > 0
			)
			.sort((a, b) => {
				const aMissing =
					a.functions.missing.length + a.classes.missing.length + a.methods.missing.length;
				const bMissing =
					b.functions.missing.length + b.classes.missing.length + b.methods.missing.length;
				return bMissing - aMissing;
			})
			.slice(0, 10);

		for (const file of sorted) {
			const totalMissing =
				file.functions.missing.length + file.classes.missing.length + file.methods.missing.length;
			console.log(`${file.path} (${totalMissing} missing)`);

			if (file.classes.missing.length > 0) {
				console.log(
					`  Classes: ${file.classes.missing.map((c) => `${c.name}:${c.line}`).join(', ')}`
				);
			}
			if (file.functions.missing.length > 0) {
				console.log(
					`  Functions: ${file.functions.missing.map((f) => `${f.name}:${f.line}`).join(', ')}`
				);
			}
			if (file.methods.missing.length > 0) {
				console.log(
					`  Methods: ${file.methods.missing.map((m) => `${m.name}:${m.line}`).join(', ')}`
				);
			}
			console.log();
		}
	}

	// Exit with error if below threshold
	const threshold = 60;
	if (parseFloat(overallCoverage) < threshold) {
		console.log(`❌ Coverage ${overallCoverage}% is below threshold ${threshold}%`);
		process.exit(1);
	} else {
		console.log(`✅ Coverage ${overallCoverage}% meets threshold ${threshold}%`);
		process.exit(0);
	}
}

main();
