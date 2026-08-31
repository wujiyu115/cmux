#!/usr/bin/env bash
#
# Re-vendor the pinned tree-sitter core + grammar sources into third_party/.
#
# The C sources are committed to the repo so that `flutter test` / `flutter
# build` work offline with no network or git-submodule dependency. Run this
# script only when bumping a pinned version; update third_party/README.md with
# the new tag + commit SHA afterwards.
#
# Every bundled grammar (and its external scanner) is plain C — no C++ scanner —
# so they all link into the single C11 native asset built by hook/build.dart.
#
# Usage: tool/fetch_grammars.sh
set -euo pipefail

# --- Pinned versions -------------------------------------------------------
# Keep these in sync with third_party/README.md.
TREE_SITTER_REPO="https://github.com/tree-sitter/tree-sitter.git"
TREE_SITTER_TAG="v0.25.10"

# Grammars vendored with a plain `src/` layout (parser.c + optional scanner.c +
# generated tree_sitter/ ABI headers). Format: "name|repo|ref".
SIMPLE_GRAMMARS=(
  "json|https://github.com/tree-sitter/tree-sitter-json.git|v0.24.8"
  "dart|https://github.com/UserNobody14/tree-sitter-dart.git|be07cf7118d3dba06236a3f19541685a68209934"
  "yaml|https://github.com/tree-sitter-grammars/tree-sitter-yaml.git|v0.7.2"
  "python|https://github.com/tree-sitter/tree-sitter-python.git|v0.23.6"
  "rust|https://github.com/tree-sitter/tree-sitter-rust.git|v0.24.0"
  "bash|https://github.com/tree-sitter/tree-sitter-bash.git|v0.25.0"
  "toml|https://github.com/tree-sitter-grammars/tree-sitter-toml.git|v0.7.0"
  "css|https://github.com/tree-sitter/tree-sitter-css.git|v0.23.2"
  "lua|https://github.com/tree-sitter-grammars/tree-sitter-lua.git|v0.5.0"
  "c|https://github.com/tree-sitter/tree-sitter-c.git|v0.24.2"
  "cpp|https://github.com/tree-sitter/tree-sitter-cpp.git|v0.23.4"
  "java|https://github.com/tree-sitter/tree-sitter-java.git|v0.23.5"
  "go|https://github.com/tree-sitter/tree-sitter-go.git|v0.25.0"
  "c-sharp|https://github.com/tree-sitter/tree-sitter-c-sharp.git|v0.23.5"
  "ruby|https://github.com/tree-sitter/tree-sitter-ruby.git|v0.23.1"
  "kotlin|https://github.com/fwcd/tree-sitter-kotlin.git|v0.3.8"
  "html|https://github.com/tree-sitter/tree-sitter-html.git|v0.23.2"
  "scss|https://github.com/tree-sitter-grammars/tree-sitter-scss.git|v1.0.0"
)

# Multi-grammar repos where we vendor one sub-grammar plus a shared common/
# scanner header. Format: "name|repo|ref|subdir".
#   typescript: the `tsx` grammar (superset that also parses .ts / .js / .jsx).
#   xml:        the `xml` grammar (the repo also ships a `dtd` grammar).
# Both scanners #include "../../common/scanner.h".
COMMON_GRAMMARS=(
  "typescript|https://github.com/tree-sitter/tree-sitter-typescript.git|v0.23.2|tsx"
  "xml|https://github.com/tree-sitter-grammars/tree-sitter-xml.git|v0.7.0|xml"
  "php|https://github.com/tree-sitter/tree-sitter-php.git|v0.24.2|php"
)

# Swift and SQL publish no generated parser.c at any tag — their src/ ships only
# grammar.js + scanner.c. Generate parser.c with the pinned tree-sitter CLI
# (tree-sitter-cli 0.25.6 matches core v0.25.10's ABI 15) before copying.
GENERATED_GRAMMARS=(
  "swift|https://github.com/alex-pinkus/tree-sitter-swift.git|0.7.3"
  "sql|https://github.com/DerekStride/tree-sitter-sql.git|v0.3.11"
)

# Markdown ships two grammars in sub-packages; we vendor only the block grammar
# (tree-sitter-markdown) for minimal-but-useful headings/code/list highlighting.
MARKDOWN_REPO="https://github.com/tree-sitter-grammars/tree-sitter-markdown.git"
MARKDOWN_TAG="v0.5.3"
MARKDOWN_SUBDIR="tree-sitter-markdown"
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
THIRD_PARTY="$PKG_DIR/third_party"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

clone_ref() {
  local repo="$1" ref="$2" dest="$3"
  # Shallow clone the tag if possible; fall back to full clone + checkout for
  # pinned commit SHAs (some grammars, e.g. dart, publish no release tags).
  if git clone --quiet --depth 1 --branch "$ref" "$repo" "$dest" 2>/dev/null; then
    :
  else
    git clone --quiet "$repo" "$dest"
    git -C "$dest" checkout --quiet "$ref"
  fi
  echo "  $repo @ $ref -> $(git -C "$dest" rev-parse HEAD)"
}

echo "Fetching tree-sitter core..."
clone_ref "$TREE_SITTER_REPO" "$TREE_SITTER_TAG" "$WORK/tree-sitter"

echo "Vendoring tree-sitter core..."
rm -rf "$THIRD_PARTY/tree-sitter/lib"
mkdir -p \
  "$THIRD_PARTY/tree-sitter/lib/src" \
  "$THIRD_PARTY/tree-sitter/lib/include/tree_sitter"
# tree-sitter core: `lib/src` unity build (lib.c) + public include headers.
cp -r "$WORK/tree-sitter/lib/src/." "$THIRD_PARTY/tree-sitter/lib/src/"
cp "$WORK/tree-sitter/lib/include/tree_sitter/api.h" \
  "$THIRD_PARTY/tree-sitter/lib/include/tree_sitter/"
cp "$WORK/tree-sitter/LICENSE" "$THIRD_PARTY/tree-sitter/LICENSE"

for entry in "${SIMPLE_GRAMMARS[@]}"; do
  IFS='|' read -r name repo ref <<<"$entry"
  echo "Fetching tree-sitter-$name..."
  clone_ref "$repo" "$ref" "$WORK/tree-sitter-$name"
  dest="$THIRD_PARTY/tree-sitter-$name"
  rm -rf "$dest/src"
  mkdir -p "$dest/src"
  cp -r "$WORK/tree-sitter-$name/src/." "$dest/src/"
  # Most grammars ship `LICENSE`; some (e.g. lua) name it `LICENSE.md`.
  if [[ -f "$WORK/tree-sitter-$name/LICENSE" ]]; then
    cp "$WORK/tree-sitter-$name/LICENSE" "$dest/LICENSE"
  else
    cp "$WORK/tree-sitter-$name/LICENSE.md" "$dest/LICENSE"
  fi
done

for entry in "${COMMON_GRAMMARS[@]}"; do
  IFS='|' read -r name repo ref subdir <<<"$entry"
  echo "Fetching tree-sitter-$name ($subdir)..."
  clone_ref "$repo" "$ref" "$WORK/tree-sitter-$name"
  dest="$THIRD_PARTY/tree-sitter-$name"
  rm -rf "$dest/$subdir/src" "$dest/common"
  mkdir -p "$dest/$subdir/src" "$dest/common"
  cp -r "$WORK/tree-sitter-$name/$subdir/src/." "$dest/$subdir/src/"
  cp "$WORK/tree-sitter-$name/common/scanner.h" "$dest/common/scanner.h"
  if [[ -f "$WORK/tree-sitter-$name/LICENSE" ]]; then
    cp "$WORK/tree-sitter-$name/LICENSE" "$dest/LICENSE"
  else
    cp "$WORK/tree-sitter-$name/LICENSE.md" "$dest/LICENSE"
  fi
done

for entry in "${GENERATED_GRAMMARS[@]}"; do
  IFS='|' read -r name repo ref <<<"$entry"
  echo "Fetching tree-sitter-$name (generating parser.c via tree-sitter-cli)..."
  clone_ref "$repo" "$ref" "$WORK/tree-sitter-$name"
  (cd "$WORK/tree-sitter-$name" && npx -y tree-sitter-cli@0.25.6 generate)
  dest="$THIRD_PARTY/tree-sitter-$name"
  rm -rf "$dest/src"
  mkdir -p "$dest/src"
  cp -r "$WORK/tree-sitter-$name/src/." "$dest/src/"
  if [[ -f "$WORK/tree-sitter-$name/LICENSE" ]]; then
    cp "$WORK/tree-sitter-$name/LICENSE" "$dest/LICENSE"
  else
    cp "$WORK/tree-sitter-$name/LICENSE.md" "$dest/LICENSE"
  fi
done

echo "Fetching tree-sitter-markdown ($MARKDOWN_SUBDIR)..."
clone_ref "$MARKDOWN_REPO" "$MARKDOWN_TAG" "$WORK/tree-sitter-markdown"
dest="$THIRD_PARTY/tree-sitter-markdown"
rm -rf "$dest/src"
mkdir -p "$dest/src"
cp -r "$WORK/tree-sitter-markdown/$MARKDOWN_SUBDIR/src/." "$dest/src/"
cp "$WORK/tree-sitter-markdown/LICENSE" "$dest/LICENSE"

echo "Done. Review 'git diff third_party/' and update third_party/README.md."
