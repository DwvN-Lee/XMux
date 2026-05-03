class Xmux < Formula
  desc "Codex-led tmux teammate runtime"
  homepage "https://github.com/DvwN-Lee/XMux"
  url "https://github.com/DvwN-Lee/XMux/releases/download/v1.0.35/xmux-1.0.35.tar.gz"
  sha256 "562e8e26a964213ec5e15199d666dcc62478bddcc5f91bf2c78ba8db3a5a91e8"
  license "MIT"
  head "https://github.com/DvwN-Lee/XMux.git", branch: "main"

  depends_on "node"
  depends_on "python@3.14"
  depends_on "tmux"
  depends_on "zsh"

  def install
    libexec.install "bin"
    libexec.install "xmux.zsh"
    libexec.install "xmux-bridge.zsh"
    libexec.install "bridge-mcp-server.js"
    libexec.install "xmux-lead-mcp-server.js"
    libexec.install "scripts"
    libexec.install "prompt"
    libexec.install "share" if buildpath.join("share").directory?

    chmod 0755, libexec/"bin/xmux"
    chmod 0755, libexec/"bridge-mcp-server.js"
    chmod 0755, libexec/"xmux-lead-mcp-server.js"

    (bin/"xmux").write <<~ZSH
      #!/usr/bin/env zsh
      set -euo pipefail
      export PATH="#{Formula["python@3.14"].opt_libexec}/bin:$PATH"
      export XMUX_INSTALL_DIR="#{libexec}"
      exec "#{libexec}/bin/xmux" "$@"
    ZSH

    zsh_completion.install "share/zsh/site-functions/_xmux" if buildpath.join("share/zsh/site-functions/_xmux").file?
  end

  test do
    assert_match "xmux 1.0.35", shell_output("#{bin}/xmux --version")

    (testpath/".codex").mkpath
    system "zsh", "-f", "-c", <<~ZSH
      set -euo pipefail
      cd "#{testpath}"
      export XMUX_INSTALL_DIR="#{libexec}"
      source "#{libexec}/xmux.zsh"
      test "$XMUX_INSTALL_DIR" = "#{libexec}"
      test "$XMUX_PROJECT_DIR" = "#{testpath}"
      test "$XMUX_STATE_DIR" = "#{testpath}/.codex/xmux"
      "#{libexec}/bin/xmux" --help >/dev/null 2>&1
    ZSH
  end
end
