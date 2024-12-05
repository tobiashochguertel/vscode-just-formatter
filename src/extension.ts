import * as vscode from "vscode";
import { formatDocument } from "./formatter";

export function activate(context: vscode.ExtensionContext) {
    const formatter = vscode.languages.registerDocumentFormattingEditProvider(
        { language: "just" },
        {
            provideDocumentFormattingEdits(document: vscode.TextDocument): vscode.ProviderResult<vscode.TextEdit[]> {
                return formatDocument(document);
            }
        }
    );

    context.subscriptions.push(formatter);
}