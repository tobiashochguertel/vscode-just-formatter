import * as assert from "assert";
import * as vscode from "vscode";
import * as path from "path";
import * as fs from "fs";
import { execSync } from "child_process";
import { suite } from "node:test";

suite("Just Formatter Extension Tests", function () {
	const loggerFilename = "../../logs/just-formatter.log"
	const fixturesPath = path.join(__dirname, "../../test-fixtures");
	const sampleFilePath = path.normalize(path.join(fixturesPath, `sample.justfile`));
	const formattedSampleFilePath = path.normalize(path.join(fixturesPath, `/formatted.justfile`));

	setup(async function () {
		if (fs.existsSync(loggerFilename)) {
			fs.unlinkSync(loggerFilename);
		}
		// Ensure the test fixture exists before running the tests.
		if (!fs.existsSync(sampleFilePath)) {
			throw new Error("Test fixture sample.justfile is missing.");
		}
		createFormattedSample(sampleFilePath, formattedSampleFilePath);
	});

	teardown(async function () {
		// Cleanup: Remove any test output files if needed.
		if (fs.existsSync(formattedSampleFilePath)) {
			fs.unlinkSync(formattedSampleFilePath);
		}
	});

	test("Extension is activated", async function () {
		const extension = vscode.extensions.getExtension("TobiasHochguertel.just-formatter");
		assert.ok(extension, "Extension should be found");
		await extension?.activate();
		const isActive = extension?.isActive;
		assert.strictEqual(isActive, true, "Extension should be activated.");
	});

	test("Formatter produces expected output", async function () {
		const document = await vscode.workspace.openTextDocument(sampleFilePath);
		const editor = await vscode.window.showTextDocument(document);

		// Invoke the formatting command programmatically.
		await vscode.commands.executeCommand("editor.action.formatDocument");

		const formattedContent = editor.document.getText();

		const expectedFormattedContent = fs.readFileSync(formattedSampleFilePath, 'utf8');

		// Check if the formatted content matches the expected content.
		assert.strictEqual(formattedContent, expectedFormattedContent, "Formatted content should match `just --fmt` output.");
	});
});

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
