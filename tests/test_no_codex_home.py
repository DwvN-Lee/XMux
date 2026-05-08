from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
LIVE_FILES = [
    ROOT / "xmux.zsh",
    ROOT / "xmux-bridge.zsh",
    ROOT / "bridge-mcp-server.js",
    ROOT / "xmux-lead-mcp-server.js",
    ROOT / "scripts" / "setup_claude_mcp.js",
    ROOT / "scripts" / "setup_xmux_codex_mcp.js",
    ROOT / "dist" / "bin" / "xmux-mailbox.js",
]


def _live_text() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in LIVE_FILES)


def test_live_code_does_not_inject_isolated_codex_home():
    text = _live_text()

    assert "CODEX_" + "HOME=" not in text
    assert ".codex-" + "home" not in text


def test_live_code_does_not_define_codex_teammate_paths():
    text = _live_text()

    assert "codex-" + "worker" not in text
    assert "xmux-codex()" not in text
    assert "setup_codex_mcp." not in text
