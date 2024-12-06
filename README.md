# Justfile Formatter

![Justfile Formatter Logo](images/icon.png){width=128 height=128}

A VSCode extension that provides automatic formatting for [Justfiles](https://github.com/casey/just) - the modern command runner alternative to Make. This extension is built on top of the `just` command-line tool's `--fmt` feature, ensuring consistent and reliable formatting that matches the official just formatter.

## Features

- **Automatic Formatting**: Format your Justfiles with a single command or on save
- **Smart Indentation**: Proper indentation for recipe blocks and dependencies
- **Consistent Styling**: Maintains consistent spacing and alignment using `just --fmt`
- **Fast and Reliable**: Built for performance and reliability
- **Preserves Comments**: Keeps your documentation intact while formatting

## Installation

1. Open VS Code
2. Press `Ctrl+P` / `Cmd+P` to open the Quick Open dialog
3. Type `ext install TobiasHochguertel.just-formatter`
4. Press Enter to install

## Usage

### Format on Save

The extension automatically formats your Justfile when you save it. To enable/disable this:

1. Open VS Code settings (`Ctrl+,` / `Cmd+,`)
2. Search for "Format On Save"
3. Ensure the setting is enabled

### Manual Formatting

You can also manually format your Justfile:

1. Open a Justfile
2. Press `Shift+Alt+F` (Windows/Linux) or `Shift+Option+F` (Mac)
3. Your file will be formatted instantly

### Example

Before:

```just
build:
  cargo build --release

test: build
cargo test

deploy: test
    @echo "Deploying..."
    rsync ./target/release/app server:/apps/
```

After:

```just
build:
    cargo build --release

test: build
    cargo test

deploy: test
    @echo "Deploying..."
    rsync ./target/release/app server:/apps/
```

## Requirements

- VS Code 1.94.0 or newer
- [just](https://github.com/casey/just) command-line tool version 1.36.0 or newer

  ```bash
  # Install just using cargo
  cargo install just

  # Verify installation and version
  just -V  # Should output: just 1.36.0 or newer
  ```

- A Justfile in your workspace

## Known Issues

Please report any issues on our [GitHub repository](https://github.com/tobiashochguertel/vscode-just-formatter/issues).

## Release Notes

### 0.0.4

- Current release

### 0.0.3

- Added icon and improved marketplace presentation
- Fixed formatting issues with nested recipes
- Improved error handling

### 0.0.2

- Initial release of just-formatter
- Basic formatting functionality

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. Visit our [GitHub repository](https://github.com/tobiashochguertel/vscode-just-formatter) for more information.

## License

This extension is licensed under the [MIT License](LICENSE).

---

**Enjoy using Justfile Formatter!**
