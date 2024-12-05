import * as assert from "assert";
import * as vscode from "vscode";
import * as path from "path";
import * as fs from "fs";
import { execSync } from "child_process";
import { suite } from "node:test";

/**
 * Creates a formatted sample file by copying the original sample and applying Just formatting.
 * @param sample - Path to the original sample Justfile.
 * @param formatted - Path where the formatted sample will be saved.
 */
function createFormattedSample(sample: string, formatted: string) {
	fs.copyFileSync(sample, formatted);
	execSync(`just --fmt --unstable --justfile ${path.basename(formatted)}`, {
		cwd: path.dirname(formatted),
	}).toString();
}

const loggerFilename = path.join(__dirname, "../../logs/just-formatter.log");
suite("Just Formatter Extension Tests", function () {
	const workspacePath = path.join(__dirname, "../../test-workspace");
	const fixturesPath = path.join(__dirname, "../../test-fixtures");
	const sample = "sample.justfile"

	const getSample = (filename: string): string => path.normalize(path.join(fixturesPath, filename));
	const getFormattedSample = (filename: string): string => path.normalize(path.join(fixturesPath, `formatted.${filename}`));
	const getFileInWorkspace = (filename: string): string => path.normalize(path.join(workspacePath, filename));

	/**
	 * Prepares the test environment by ensuring the sample Justfile exists and is copied to the workspace.
	 * It also creates a formatted version of the sample for comparison.
	 * @throws Error if the sample Justfile is missing in the fixtures directory.
	 */
	function prepareForTest() {
		const samplePath = getSample(sample);
		if (!fs.existsSync(samplePath)) {
			throw new Error(`Test fixture "${path.basename(samplePath)}" is missing in the fixtures directory "${fixturesPath}".`);
		}
		fs.mkdirSync(workspacePath);
		createFormattedSample(samplePath, getFormattedSample(sample));
		fs.copyFileSync(samplePath, getFileInWorkspace(sample));
	}

	setup(async function () {
		if (fs.existsSync(workspacePath)) {
			console.log(`Cleaning up old workspace... ${workspacePath}`);
			fs.rmSync(workspacePath, { recursive: true, force: true });
		}
		if (fs.existsSync(loggerFilename)) {
			console.log(`Cleaning up old log file... ${loggerFilename}`);
			fs.unlinkSync(loggerFilename);
		}
		const formattedSample = getFormattedSample(sample);
		if (fs.existsSync(formattedSample)) {
			// Cleanup: Remove any test output files if needed.
			console.log(`Cleaning up old formatted file... ${formattedSample}`);
			fs.unlinkSync(formattedSample);
		}
		prepareForTest();
	});

	teardown(async function () {

	});

	test("Extension is activated", async function () {
		const extension = vscode.extensions.getExtension("TobiasHochguertel.just-formatter");
		assert.ok(extension, "Extension should be found");
		await extension?.activate();
		const isActive = extension?.isActive;
		assert.strictEqual(isActive, true, "Extension should be activated.");
	});

	test("Formatter produces expected output", async function () {
		const document = await vscode.workspace.openTextDocument(getFileInWorkspace(sample));
		const editor = await vscode.window.showTextDocument(document);

		// Invoke the formatting command programmatically.
		await vscode.commands.executeCommand("editor.action.formatDocument");

		const formattedContent = editor.document.getText();

		const expectedFormattedContent = fs.readFileSync(getFormattedSample(sample), 'utf8');

		// Check if the formatted content matches the expected content.
		assert.strictEqual(formattedContent, expectedFormattedContent, "Formatted content should match `just --fmt` output.");
	});

});
