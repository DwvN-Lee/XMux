# Mirrored to DwvN-Lee/homebrew-xmux:Formula/xmux.rb during release.
# Update this XMux repository copy first; do not hand-edit the tap copy as SSOT.
class Xmux < Formula
  desc "Codex-led tmux teammate runtime"
  homepage "https://github.com/DwvN-Lee/XMux"
  url "https://github.com/DwvN-Lee/XMux/releases/download/v1.0.40/xmux-1.0.40.tar.gz"
  sha256 "166476ca5254222955bb9e0fe1a17cf7c642e8b823985a5c2032b28e2052f446"
  license "MIT"
  head "https://github.com/DwvN-Lee/XMux.git", branch: "main"

  depends_on "node"
  depends_on "tmux"
  depends_on "zsh"

  def install
    libexec.install "bin"
    libexec.install "xmux.zsh"
    libexec.install "xmux-bridge.zsh"
    libexec.install "bridge-mcp-server.js"
    libexec.install "xmux-lead-mcp-server.js"
    libexec.install "package.json"
    libexec.install "dist"
    libexec.install "src"
    libexec.install "scripts"
    libexec.install "prompt"
    libexec.install "share" if buildpath.join("share").directory?

    chmod 0755, libexec/"bin/xmux"
    chmod 0755, libexec/"bridge-mcp-server.js"
    chmod 0755, libexec/"xmux-lead-mcp-server.js"
    chmod 0755, libexec/"dist/bin/xmux-mailbox.js"

    (bin/"xmux").write <<~ZSH
      #!/usr/bin/env zsh
      set -euo pipefail
      export XMUX_INSTALL_DIR="#{opt_libexec}"
      exec "#{opt_libexec}/bin/xmux" "$@"
    ZSH

    zsh_completion.install "share/zsh/site-functions/_xmux" if buildpath.join("share/zsh/site-functions/_xmux").file?
  end

  test do
    assert_match "xmux 1.0.40", shell_output("#{bin}/xmux --version")

    (testpath/".codex").mkpath
    system "zsh", "-f", "-c", <<~ZSH
      set -euo pipefail
      cd "#{testpath}"
      export XMUX_INSTALL_DIR="#{opt_libexec}"
      source "#{opt_libexec}/xmux.zsh"
      test "$XMUX_INSTALL_DIR" = "#{opt_libexec}"
      test "$XMUX_PROJECT_DIR" = "#{testpath}"
      test "$XMUX_STATE_DIR" = "#{testpath}/.codex/xmux"
      "#{opt_libexec}/bin/xmux" --help >/dev/null 2>&1
    ZSH
  end
end
