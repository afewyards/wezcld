# Automatic Versioning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add automatic semantic versioning via go-semantic-release, callable with `wezcld --version`.

**Architecture:** VERSION file at repo root, committed by go-semantic-release in GH Actions. `wezcld --version` reads `$SHIM_DIR/VERSION`. Installer embeds VERSION alongside bin/ scripts.

**Tech Stack:** POSIX sh, go-semantic-release, GitHub Actions, softprops/action-gh-release

---

### Task 1: Add `--version` flag to wezcld

**Files:**
- Modify: `bin/wezcld:4-22` (insert after `--uninstall` block, before WezTerm detection)

**Step 1: Write failing tests**

Add to `tests/integration-test.sh` after Test 13 (log format test), before Group 2:

```sh
# Test 14: wezcld --version with VERSION file
echo "1.2.3" > "$SHIM_DIR/VERSION"
version_output=$("$SHIM_DIR/bin/wezcld" --version 2>&1)
rm -f "$SHIM_DIR/VERSION"
if [ "$version_output" = "wezcld 1.2.3" ]; then
    pass "wezcld --version with VERSION file outputs 'wezcld 1.2.3'"
else
    fail "wezcld --version with VERSION file outputs 'wezcld 1.2.3'" "got '$version_output'"
fi

# Test 15: wezcld -v with VERSION file
echo "1.2.3" > "$SHIM_DIR/VERSION"
version_output=$("$SHIM_DIR/bin/wezcld" -v 2>&1)
rm -f "$SHIM_DIR/VERSION"
if [ "$version_output" = "wezcld 1.2.3" ]; then
    pass "wezcld -v with VERSION file outputs 'wezcld 1.2.3'"
else
    fail "wezcld -v with VERSION file outputs 'wezcld 1.2.3'" "got '$version_output'"
fi

# Test 16: wezcld --version without VERSION file outputs 'wezcld dev'
version_output=$("$SHIM_DIR/bin/wezcld" --version 2>&1)
if [ "$version_output" = "wezcld dev" ]; then
    pass "wezcld --version without VERSION file outputs 'wezcld dev'"
else
    fail "wezcld --version without VERSION file outputs 'wezcld dev'" "got '$version_output'"
fi
```

Note: existing Group 2 test numbers shift by 3 (old 14→17, etc). Update comments accordingly.

**Step 2: Run tests to verify they fail**

Run: `sh tests/integration-test.sh`
Expected: FAIL — `wezcld` doesn't handle `--version` yet

**Step 3: Implement `--version` in bin/wezcld**

Insert after the `--uninstall` block (after line 22), before `# Detect WezTerm`:

```sh
# Version
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
    VER="dev"
    [ -f "$SHIM_DIR/VERSION" ] && VER="$(cat "$SHIM_DIR/VERSION")"
    echo "wezcld $VER"
    exit 0
fi
```

Problem: `$SHIM_DIR` is resolved on lines 31-40 (after the WezTerm check). Move the `--version` block AFTER the `SHIM_DIR` resolution (line 40), but BEFORE the state directory init (line 43). The full order becomes:

1. `--uninstall` (lines 4-22)
2. WezTerm detection (lines 24-28) — **but `--version` should work outside WezTerm too**

So we need to resolve `SHIM_DIR` earlier. Move the path resolution block (lines 30-40) to right after `--uninstall`, before WezTerm detection. Then add `--version` check. New order:

```
--uninstall block
path resolution (SHIM_DIR)
--version check
WezTerm detection
state dir init
env vars + exec claude
```

**Step 4: Run tests to verify they pass**

Run: `sh tests/integration-test.sh`
Expected: PASS

**Step 5: Commit**

```
git add bin/wezcld tests/integration-test.sh
git commit -m "feat(version): add --version flag to wezcld"
```

---

### Task 2: Create VERSION file and update build-installer.sh

**Files:**
- Create: `VERSION` (repo root)
- Modify: `scripts/build-installer.sh:65-68` (add VERSION embedding after bin/wezcld)

**Step 1: Create VERSION file**

```
0.0.0
```

Initial placeholder — go-semantic-release will overwrite on first release.

**Step 2: Update build-installer.sh to embed VERSION**

After the `# Embed bin/wezcld` block (line 68), add:

```sh
# Embed VERSION
printf 'cat > "$INSTALL_DIR/VERSION" << '"'"'VERSION_EOF'"'"'\n' >> "$OUT"
cat "$REPO_DIR/VERSION" >> "$OUT"
printf 'VERSION_EOF\n\n' >> "$OUT"
```

**Step 3: Run build-installer.sh and verify**

Run: `sh scripts/build-installer.sh`
Verify: `grep -A2 'VERSION_EOF' install.sh` shows the VERSION content embedded

**Step 4: Commit**

```
git add VERSION scripts/build-installer.sh install.sh
git commit -m "chore(version): add VERSION file and embed in installer"
```

---

### Task 3: Create GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Step 1: Create workflow file**

```yaml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: go-semantic-release/action@v1
        id: semrel
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          allow-initial-development-versions: true

      - name: Update VERSION and rebuild installer
        if: steps.semrel.outputs.version != ''
        run: |
          echo "${{ steps.semrel.outputs.version }}" > VERSION
          sh scripts/build-installer.sh
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add VERSION install.sh
          git commit -m "chore(release): ${{ steps.semrel.outputs.version }} [skip ci]"
          git push

      - name: Create GitHub Release
        if: steps.semrel.outputs.version != ''
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ steps.semrel.outputs.version }}
          files: install.sh
          generate_release_notes: true
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`
Expected: No error

**Step 3: Commit**

```
git add .github/workflows/release.yml
git commit -m "ci(release): add go-semantic-release workflow"
```

---

### Task 4: Update README with version badge and install URL

**Files:**
- Modify: `README.md` (add version badge, update install URL to use GH Release)

**Step 1: Add version badge**

At top of README, after the title line, add:

```markdown
[![Release](https://img.shields.io/github/v/release/afewyards/wezcld)](https://github.com/afewyards/wezcld/releases/latest)
```

**Step 2: Commit**

```
git add README.md
git commit -m "docs(readme): add release version badge"
```
