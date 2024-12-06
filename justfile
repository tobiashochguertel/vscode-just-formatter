# https://just.systems/man/en/

set shell := ["zsh", "-cu"]

# Variables

GREETING := "Hello, World!"
ROCKSPEC_FILE := "cli-generate-prompt-dev-1.rockspec"
ROCKSPEC_BACKUP := "cli-generate-prompt-dev-1 copy.rockspec"
INSPECT_DEPENDENCY := "inspect >= 3.1"
ANSICOLORS_DEPENDENCY := "ansicolors >= 1.0.0"
browse := if os() == "linux" { "xdg-open " } else { "open" }
copy := if os() == "linux" { "xsel -ib" } else { "pbcopy" }
replace := if os() == "linux" { "sed -i" } else { "sed -i '' -e" }
date_suffix := `echo test_$(date +%F)`

# Default task
@default:
    just help

# List tasks
@help:
    just --list

# Interactive task chooser
@choose:
    just --choose

# Print the contents of `./justfile`
@self:
    bat --plain -n --language=make ./justfile

# As tldr, gives a summarized man-page
cheats CMD:
    @curl -sS cheat.sh/{{ CMD }} | bat --style=plain

# Search through the history with fzf
dejavu WORD:
    @c -R ~/.zsh_history && fc -l | awk '{$1=""; print $0}' | sort | uniq | fzf --tac --layout=reverse --height=40% +s -e -q "{{ WORD }}"

# Lint task
lint:
    luarocks lint {{ ROCKSPEC_FILE }}

# Add dependency
add-dependency DEPENDENCY:
    add_dependency ./{{ ROCKSPEC_FILE }} "{{ DEPENDENCY }}"

# Add dependencies for specific environments
add-dependency-env ENV DEPENDENCY='':
    #!/usr/bin/env sh
    if [ "{{ ENV }}" = "dev" ]; then
      cp -f "{{ ROCKSPEC_BACKUP }}" "{{ ROCKSPEC_FILE }}"
    fi
    if [ -n "{{ DEPENDENCY }}" ]; then
      just add-dependency "{{ DEPENDENCY }}"
    else
      if [ "{{ ENV }}" = "dev" ]; then
        just add-dependency {{ INSPECT_DEPENDENCY }}
      else
        just add-dependency {{ ANSICOLORS_DEPENDENCY }}
      fi
    fi

# Usage
add-dev-dependency:
    just add-dependency-env dev {{ INSPECT_DEPENDENCY }}

add-prod-dependency:
    just add-dependency-env prod {{ ANSICOLORS_DEPENDENCY }}

# Watch tasks
watch TASK:
    find . -name '*.lua' | entr just {{ TASK }}

# Example watch tasks
watch-add-dependency-dev:
    just watch add-dependency-dev

watch-add-dependency-prod:
    just watch add-dependency-prod

# ---

# Run tests
test TYPE="luarocks":
    #!/usr/bin/env bash
    if [ "{{ TYPE }}" = "luarocks" ]; then
        luarocks test
    else
        busted tests/
    fi

# Watch and run tests
watch-test TYPE="luarocks":
    find . -name '*.lua' | entr just test {{ TYPE }}

# Usage examples
test-luarocks:
    just test luarocks

test-busted:
    just test busted

watch-test-luarocks:
    just watch-test luarocks

watch-test-busted:
    just watch-test busted
