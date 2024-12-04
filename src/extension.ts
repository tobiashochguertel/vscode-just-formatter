import * as vscode from "vscode";
import { exec } from "child_process";

export function activate(context: vscode.ExtensionContext) {
    const formatter = vscode.languages.registerDocumentFormattingEditProvider(
        { language: "just" },
        {
            provideDocumentFormattingEdits(document: vscode.TextDocument) {
                return new Promise((resolve, reject) => {
                    exec("just --fmt --unstable --justfile", { cwd: vscode.workspace.rootPath }, (err, stdout) => {
                        if (err) {
                            vscode.window.showErrorMessage("Error formatting Justfile: " + err.message);
                            return reject(err);
                        }
                        const fullRange = new vscode.Range(
                            document.positionAt(0),
                            document.positionAt(document.getText().length)
                        );
                        resolve([vscode.TextEdit.replace(fullRange, stdout)]);
                    });
                });
            },
        }
    );

    context.subscriptions.push(formatter);
}