#!/bin/sh
set -eu

nix develop .#ci --command stylua --check .
git ls-files '*.lua' | xargs nix develop .#ci --command selene --display-style quiet
nix develop .#ci --command prettier --check .
nix fmt
git diff --exit-code -- '*.nix'
CANOLA_LIB=$(test -d _canola && echo _canola || echo "$HOME/dev/canola.nvim")/lua
LUARC_TMP=$(mktemp --suffix=.json)
python3 -c "
import json, sys
with open('.luarc.json') as f: cfg = json.load(f)
cfg.setdefault('workspace', {}).setdefault('library', []).append(sys.argv[1])
print(json.dumps(cfg))
" "$CANOLA_LIB" > "$LUARC_TMP"
nix develop .#ci --command lua-language-server --check lua --checklevel=Error \
  --configpath="$LUARC_TMP"
rm -f "$LUARC_TMP"
nix develop .#ci --command vimdoc-language-server check doc/ --no-runtime-tags
nix develop .#ci --command busted
