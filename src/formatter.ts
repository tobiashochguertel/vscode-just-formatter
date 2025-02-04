import { exec } from "child_process";
import * as vscode from 'vscode';
import { documentToString, LoggerOutputType, minilogger } from "./utils/minilogger";

export function formatDocument(document: vscode.TextDocument): Promise<vscode.TextEdit[]> {
    const log = minilogger(LoggerOutputType.OUTPUT_CHANNEL);
    log("Formatting Justfile...");
    log("vscode.TextDocument: ", documentToString(document));
    const justFmtCommand = `just --fmt --unstable --justfile ${document.fileName}`;
    return new Promise((resolve, reject) => {
        try {
            const cwd = document.uri.fsPath.split('/').slice(0, -1).join('/');
            exec(justFmtCommand, { cwd }, (err, stdout) => {
                if (err) {
                    if (err instanceof Error) {
                        log(`Error formatting Justfile: ${err.message}`);
                        vscode.window.showErrorMessage("Error formatting Justfile: " + err.message);
                    } else {
                        log(`Error formatting Justfile: ${String(err)}`);
                        vscode.window.showErrorMessage("Error formatting Justfile: " + String(err));
                    }
                    return reject(err);
                }
                log('Formatting successful.');
                if (!stdout) {
                    log('No output from just command.');
                    // Revert the file to load the changes from disk (in the context of VS Code, it actually means "revert to the version on disk".)
                    vscode.commands.executeCommand("workbench.action.files.revert", document.uri).then(() => {
                        // Return an empty array to indicate no text edits are needed
                        return resolve([]);
                    });
                }
                log('stdout: ', stdout);
            });
        } catch (err) {
            if (err instanceof Error) {
                log(`Error formatting Justfile: ${err.message}`);
                vscode.window.showErrorMessage("Error formatting Justfile: " + err.message);
            } else {
                log(`Error formatting Justfile: ${String(err)}`);
                vscode.window.showErrorMessage("Error formatting Justfile: " + String(err));
            }
            return reject(err);
        }
    });

}