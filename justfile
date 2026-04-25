default:
    @just --list

format:
    nix fmt -- --ci
    stylua --check .
    biome check .

lint:
    git ls-files '*.lua' | xargs selene --display-style quiet
    sh -ceu 'canola_lib=$(test -d _canola && echo _canola || echo "$HOME/dev/canola.nvim")/lua; luarc_tmp=$(mktemp --suffix=.json); trap "rm -f \"$luarc_tmp\"" EXIT; python3 -c "import json, sys; cfg = json.load(open(\".luarc.json\")); cfg.setdefault(\"workspace\", {}).setdefault(\"library\", []).append(sys.argv[1]); print(json.dumps(cfg))" "$canola_lib" > "$luarc_tmp"; lua-language-server --check lua --checklevel=Error --configpath="$luarc_tmp"'
    vimdoc-language-server check doc/

test:
    busted

ci: format lint test
    @:
