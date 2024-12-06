import * as vscode from "vscode";
import path from 'path';
const __dirname = path.dirname(__filename);
import fs from 'fs';

export enum LoggerOutputType {
    CONSOLE = "console",
    OUTPUT_CHANNEL = "OutputChannel"
}

export type Logger = (...messages: string[]) => void

export function documentToString(document: vscode.TextDocument): string {
    const documentCopy = { ...document, content: document.getText(), uri: document.uri.toString() };
    return JSON.stringify(documentCopy, null, 2);
}

export function rangeToString(range: vscode.Range): string {
    return JSON.stringify(range, null, 2);
}

export const minilogger = (outputType: LoggerOutputType = LoggerOutputType.CONSOLE): Logger => {
    switch (outputType) {
        case LoggerOutputType.OUTPUT_CHANNEL:
            console.log("minilogger: ", outputType);
            const logPath = path.join(__dirname, '../logs/just-formatter.log');
            const logDir = path.dirname(logPath);
            if (!fs.existsSync(logDir)) {
                fs.mkdirSync(logDir, { recursive: true });
                console.log(`Log directory created: ${logDir}`);
            }
            if (!fs.existsSync(logPath)) {
                fs.writeFileSync(logPath, 'New Logfile\n');
                console.log(`Logfile created!`);
            }
            console.log(`Log file path: ${logPath}`);
            const outputChannel = vscode.window.createOutputChannel('Just Formatter');
            return (...messages: string[]) => {
                let message = ""
                messages.forEach(m => {
                    message += `${m}\n`
                });
                // Write to the destinations:
                outputChannel.appendLine(`${message}\n`)
                try {
                    if (!fs.existsSync(logPath)) {
                        fs.writeFileSync(logPath, 'New Logfile\n');
                    }
                    fs.appendFileSync(logPath, `${message}\n`);
                } catch (error) {
                    throw new Error(`Failed to write to log file: ${error}`);
                }
            }
            break;
        case LoggerOutputType.CONSOLE:
            console.log("minilogger: ", outputType);
            return (...messages: string[]) => {
                console.log(...messages);
            };
            break;
        default:
            console.log("minilogger: ", outputType);
            throw new Error(`Invalid output type specified for minilogger ${outputType}`);
            break;
    }
};