Back to [README](../../README.md)

# Homebrew Distribution

Homebrew is the primary installation path for XMux:

```zsh
brew tap DwvN-Lee/xmux
brew install xmux
xmux setup-codex
xmux doctor-codex
xmux -n refactor
```

The Formula installs runtime files under Homebrew `libexec`:

```text
$(brew --prefix)/opt/xmux/libexec/
  bin/xmux
  xmux.zsh
  xmux-bridge.zsh
  bridge-mcp-server.js
  xmux-lead-mcp-server.js
  package.json
  dist/
  src/
  scripts/
  prompt/
  share/zsh/site-functions/_xmux
```

The Formula intentionally does not install `plugins/`, top-level `skills/`, or
Codex plugin command files into Homebrew `libexec`. Homebrew owns only the
terminal runtime.

The public `$(brew --prefix)/bin/xmux` wrapper exports:

```text
XMUX_INSTALL_DIR=$(brew --prefix)/opt/xmux/libexec
```

It then execs `libexec/bin/xmux`. Runtime asset lookups for scripts, prompts,
and MCP servers must derive from `XMUX_INSTALL_DIR`.

Project state remains separate from the install:

```text
XMUX_PROJECT_DIR=<project root>
XMUX_STATE_DIR=<project root>/.codex/xmux
```

Codex integration is a separate, explicit step:

```zsh
xmux setup-codex
xmux doctor-codex
```

`xmux setup-codex` owns `~/.codex` changes. It records `XMUX_INSTALL_DIR`, the
installed `bin` path, and a versioned npm `xmux_lead` MCP entrypoint; installs
a scoped XMux command rule; and refreshes available XMux skills under
`~/.codex/skills`. The npm entrypoint is only the MCP launcher. Homebrew remains
the runtime source of truth through `XMUX_INSTALL_DIR`. Setup must not write
global `XMUX_PROJECT_DIR` or `XMUX_STATE_DIR`, because those are inherited from
the active `xmux -n <session>` runtime.

Runtime-only package installs do not include Codex skill source files. Provide
an external source directory when skill refresh is needed:

```zsh
xmux setup-codex --skills-dir /path/to/xmux-skills
```

`XMUX_CODEX_SKILLS_DIR` provides the same source path for automation. Without
an explicit skill source, `setup-codex` skips skill refresh. It does not infer
skills from a local checkout path.

Remove only XMux-managed Codex integration state with:

```zsh
xmux remove-codex
```

## Formula SSOT

The Formula source of truth is the XMux repository file:

```text
packaging/homebrew/xmux.rb
```

The Homebrew tap repository is a distribution mirror:

```text
DwvN-Lee/homebrew-xmux
  Formula/xmux.rb
```

Do not hand-edit the tap Formula as the primary copy. During release, update
`packaging/homebrew/xmux.rb` in the XMux repo, then copy that exact file to the
tap repository.

```zsh
cp packaging/homebrew/xmux.rb ../homebrew-xmux/Formula/xmux.rb
cd ../homebrew-xmux
git diff -- Formula/xmux.rb
git commit -am "Update xmux to <version>"
git push
```

Homebrew lowercases tap paths on disk, so `brew tap DwvN-Lee/xmux` may appear
under `$(brew --prefix)/Library/Taps/dwvn-lee/homebrew-xmux`. That is expected.
There should be only one installed `xmux` Formula tap. Remove stale local taps
after the installed Formula has been moved to the official tap.

Release checklist:

```zsh
# In the XMux repository.
python3 -m pytest -q
zsh -n xmux.zsh
zsh -n xmux-bridge.zsh
node --check scripts/setup_xmux_codex_mcp.js
npm pack --dry-run

# Publish runtime artifacts.
npm publish --access public
git push origin main "v<version>"
gh release create "v<version>" "dist/xmux-<version>.tar.gz" --title "XMux <version>"

# Mirror the Formula to the Homebrew tap.
cp packaging/homebrew/xmux.rb ../homebrew-xmux/Formula/xmux.rb
cd ../homebrew-xmux
git commit -am "Update xmux to <version>"
git push

# Verify local installation and Codex MCP registration.
brew reinstall dwvn-lee/xmux/xmux
/opt/homebrew/bin/xmux setup-codex
/opt/homebrew/bin/xmux --version
codex mcp list
```
