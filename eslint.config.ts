import { ESLint, Linter } from "eslint";
import typescriptEslint from "@typescript-eslint/eslint-plugin";
import tsParser from "@typescript-eslint/parser";
import globals from "globals";

export default [
    {
        files: ["**/*.ts", "**/*.js"],
        plugins: {
            "@typescript-eslint": typescriptEslint,
        },

        languageOptions: {
            parser: tsParser,
            ecmaVersion: 2022,
            sourceType: "module",
            globals: {
                // ...globals.browser,
                ...globals.node,
                ...globals.mocha
            }
        },


        rules: {
            "@typescript-eslint/naming-convention": ["warn", {
                selector: "import",
                format: ["camelCase", "PascalCase"],
            }],

            curly: "warn",
            eqeqeq: "warn",
            "no-throw-literal": "warn",
            "no-undef": "error", // Highlight missing imports/undefined variables
            // "import/no-unresolved": "error",
            // "import/named": "error",
            // "import/default": "error",
            // "import/no-duplicates": "error"
        },
    }
    // ] satisfies Linter.Config[];
] satisfies Linter.Config[];

// find . -type f -iname eslint.config.ts | entr pnpm run checks:lint
// fd --type f *.ts . | entr pnpm run checks:lint
