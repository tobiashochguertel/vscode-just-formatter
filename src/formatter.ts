import * as vscode from 'vscode';
import { exec } from "child_process";
import { documentToString, LoggerOutputType, minilogger, rangeToString } from "./utils/minilogger";

export function formatDocument(document: vscode.TextDocument): Promise<vscode.TextEdit[]> {
    const log = minilogger(LoggerOutputType.OUTPUT_CHANNEL);
    log("Formatting Justfile...");
    log("vscode.TextDocument: ", documentToString(document));
    return new Promise((resolve, reject) => {
        try {
            const cwd = document.uri.fsPath.split('/').slice(0, -1).join('/');
            exec("just --fmt --unstable --justfile", { cwd }, (err, stdout) => {
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
                    return resolve([]);
                }
                const fullRange = new vscode.Range(
                    document.positionAt(0),
                    document.positionAt(document.getText().length)
                );
                log('fullRange: ', rangeToString(fullRange));
                log('stdout: ', stdout);
                resolve([vscode.TextEdit.replace(fullRange, stdout)]);
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