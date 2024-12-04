import * as assert from "assert";
import * as vscode from "vscode";
import * as path from "path";
import * as fs from "fs";
import { execSync } from "child_process";

suite("Just Formatter Extension Tests", function () {
	const sampleFilePath = path.join(__dirname, "../../test-fixtures/sample.justfile");
	const formattedFilePath = path.join(__dirname, "../../test-fixtures/formatted.justfile");

	setup(async function () {
		// Ensure the test fixture exists before running the tests.
		if (!fs.existsSync(sampleFilePath)) {
			throw new Error("Test fixture sample.justfile is missing.");
		}
	});

	teardown(async function () {
		// Cleanup: Remove any test output files if needed.
		if (fs.existsSync(formattedFilePath)) {
			fs.unlinkSync(formattedFilePath);
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

		// Run the `just --fmt --unstable` CLI directly for comparison.
		const expectedContent = execSync(`just --fmt --unstable --justfile ${path.basename(sampleFilePath)}`, {
			cwd: path.dirname(sampleFilePath),
		}).toString();

		// Check if the formatted content matches the expected content.
		assert.strictEqual(formattedContent, expectedContent, "Formatted content should match `just --fmt` output.");
	});
});