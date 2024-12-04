import { defineConfig } from '@vscode/test-cli';
import { fileURLToPath } from "url";
import path from 'path';
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const workspacePath = path.resolve(__dirname, "./test-fixtures");

const config = defineConfig({
	workspacePath: workspacePath,
	files: 'out/test/**/*.test.js',
	version: 'stable',
	launchArgs: [
		'--disable-extensions',
		'--user-data-dir', path.resolve(__dirname, 'test-user-data'),
		'--disable-gpu',
		'--no-sandbox'
	],
	env: {
		// Set shell environment variables separately
		SHELL: '/bin/bash',
		BASH_ENV: path.resolve(__dirname, '.bashrc_test'),
		// Additional environment variables from .bashrc_test
		NODE_ENV: 'test',
		VSCODE_TEST_DATA_DIR: path.resolve(__dirname, 'test-user-data'),
		VSCODE_EXTENSION_DIR: path.resolve(__dirname, 'test-extensions'),
		DEBUG_LOG_LEVEL: 'debug',
		DEBUG_LOG_DIR: path.resolve(__dirname, 'logs/shell_environment'),
		VSCODE_CLI_NO_UPDATE_NOTIFIER: '1',
		VSCODE_CLI_NO_TELEMETRY: '1'
	},
	mocha: {
		ui: 'tdd',
		timeout: 20000
	},
	settings: {
		'editor.fontSize': 14,
		'editor.tabSize': 4,
		'files.autoSave': 'off',
		'editor.minimap.enabled': false,
		'workbench.editor.enablePreview': false,
	}
});

// Debug: Log the configuration
console.log('Configuration:', {
	unitTestsPath: path.resolve(__dirname, 'out/tests/tests/**/*.test.js'),
	userDataDir: path.resolve(__dirname, 'test-user-data'),
	bashrcPath: path.resolve(__dirname, '.bashrc_test')
});

console.log('defineConfig Output:', config);

export default config;