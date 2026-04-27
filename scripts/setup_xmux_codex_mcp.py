#!/usr/bin/env python3
"""Install or remove the XMux Codex-lead MCP server config.

This configures Codex as the XMux lead, exposing tools such as
send_to_teammate/read_teammate_response.
"""

import os
import shutil
import sys


SERVER_NAME = "xmux_lead"
MARKETPLACE_NAME = "xmux-local"
PLUGIN_KEY = f"xmux@{MARKETPLACE_NAME}"
LEGACY_PREFIX = "a" + "mux"
LEGACY_SERVER_NAMES = (f"{LEGACY_PREFIX}_lead",)
LEGACY_MARKETPLACE_NAMES = (f"{LEGACY_PREFIX}-local",)
LEGACY_PLUGIN_KEYS = (f"{LEGACY_PREFIX}@{LEGACY_PREFIX}-local",)
LOCAL_PLUGIN_CACHE_VERSION = "local"


def resolve_path_with_node() -> str:
    node = shutil.which("node")
    if node:
        node_bin_dir = os.path.dirname(os.path.realpath(node))
    else:
        node_bin_dir = None
        nvm_dir = os.environ.get("NVM_DIR", os.path.expanduser("~/.nvm"))
        default_alias = os.path.join(nvm_dir, "alias", "default")
        if os.path.exists(default_alias):
            version = (
                os.readlink(default_alias)
                if os.path.islink(default_alias)
                else open(default_alias, encoding="utf-8").read().strip()
            )
            candidate = os.path.join(nvm_dir, "versions", "node", version, "bin")
            if os.path.isdir(candidate):
                node_bin_dir = candidate
        if not node_bin_dir:
            raise FileNotFoundError("node binary not found")

    base_dirs = [node_bin_dir, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    seen = set()
    dirs = []
    for d in base_dirs:
        if d not in seen:
            seen.add(d)
            dirs.append(d)
    return ":".join(dirs)


def read_text(path: str) -> str:
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            return f.read()
    return ""


def write_text(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def remove_toml_blocks(content: str, matcher) -> str:
    lines = content.split("\n")
    out = []
    skip = False
    for line in lines:
        stripped = line.strip()
        if matcher(stripped):
            skip = True
            continue
        if skip and stripped.startswith("[") and not matcher(stripped):
            skip = False
        if skip:
            continue
        out.append(line)
    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out)


def remove_xmux_blocks(content: str) -> str:
    server_names = (SERVER_NAME, *LEGACY_SERVER_NAMES)
    marketplace_names = (MARKETPLACE_NAME, *LEGACY_MARKETPLACE_NAMES)
    plugin_keys = (PLUGIN_KEY, *LEGACY_PLUGIN_KEYS)
    for name in server_names:
        content = remove_toml_blocks(
            content,
            lambda stripped, name=name: stripped.startswith(f"[mcp_servers.{name}"),
        )
    for name in marketplace_names:
        content = remove_toml_blocks(
            content,
            lambda stripped, name=name: stripped == f"[marketplaces.{name}]",
        )
    for key in plugin_keys:
        content = remove_toml_blocks(
            content,
            lambda stripped, key=key: stripped == f'[plugins."{key}"]',
        )
    return content


def build_plugin_block(xmux_install_dir: str) -> str:
    return f"""\
[marketplaces.{MARKETPLACE_NAME}]
source_type = "local"
source = "{xmux_install_dir}"

[plugins."{PLUGIN_KEY}"]
enabled = true
"""


def build_block(server_path: str, xmux_install_dir: str, xmux_project_dir: str,
                xmux_state_dir: str) -> str:
    path_env = resolve_path_with_node()
    home = os.path.expanduser("~")
    return f"""\
[mcp_servers.{SERVER_NAME}]
command = "node"
args = ["{server_path}"]
startup_timeout_sec = 10
tool_timeout_sec = 300

[mcp_servers.{SERVER_NAME}.env]
PATH = "{path_env}"
HOME = "{home}"
XMUX_INSTALL_DIR = "{xmux_install_dir}"
XMUX_PROJECT_DIR = "{xmux_project_dir}"
XMUX_STATE_DIR = "{xmux_state_dir}"
"""


def plugin_cache_root(config_path: str) -> str:
    codex_home = os.path.dirname(os.path.abspath(config_path))
    return os.path.join(codex_home, "plugins", "cache", MARKETPLACE_NAME, "xmux")


def plugin_cache_path(config_path: str) -> str:
    return os.path.join(plugin_cache_root(config_path), LOCAL_PLUGIN_CACHE_VERSION)


def remove_local_plugin_cache(config_path: str) -> None:
    for cache_path in (
        plugin_cache_root(config_path),
        *legacy_plugin_cache_roots(config_path),
    ):
        if os.path.islink(cache_path) or os.path.isfile(cache_path):
            os.unlink(cache_path)
        elif os.path.isdir(cache_path):
            shutil.rmtree(cache_path)


def legacy_plugin_cache_roots(config_path: str) -> tuple[str, ...]:
    codex_home = os.path.dirname(os.path.abspath(config_path))
    return tuple(
        os.path.join(codex_home, "plugins", "cache", marketplace, LEGACY_PREFIX)
        for marketplace in LEGACY_MARKETPLACE_NAMES
    )


def install_local_plugin_cache(config_path: str, xmux_install_dir: str) -> None:
    src = os.path.join(xmux_install_dir, "plugins", "xmux")
    if not os.path.isdir(src):
        return

    root = plugin_cache_root(config_path)
    if os.path.islink(root) or os.path.isfile(root):
        os.unlink(root)
    os.makedirs(root, exist_ok=True)

    dst = plugin_cache_path(config_path)
    if os.path.islink(dst) or os.path.isfile(dst):
        os.unlink(dst)
    elif os.path.isdir(dst):
        shutil.rmtree(dst)

    shutil.copytree(src, dst)


def parse_args(argv):
    opts = {
        "remove": False,
        "home": "",
        "project": "",
        "xmux_install_dir": "",
        "xmux_project_dir": "",
        "xmux_state_dir": "",
        "server_path": "",
    }
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--remove":
            opts["remove"] = True
            i += 1
        elif arg == "--home" and i + 1 < len(argv):
            opts["home"] = argv[i + 1]
            i += 2
        elif arg == "--project" and i + 1 < len(argv):
            opts["project"] = argv[i + 1]
            i += 2
        elif arg == "--xmux-install-dir" and i + 1 < len(argv):
            opts["xmux_install_dir"] = os.path.expanduser(argv[i + 1])
            i += 2
        elif arg == "--xmux-project-dir" and i + 1 < len(argv):
            opts["xmux_project_dir"] = os.path.expanduser(argv[i + 1])
            i += 2
        elif arg == "--xmux-state-dir" and i + 1 < len(argv):
            opts["xmux_state_dir"] = os.path.expanduser(argv[i + 1])
            i += 2
        elif arg == "--server-path" and i + 1 < len(argv):
            opts["server_path"] = argv[i + 1]
            i += 2
        else:
            print(f"unknown or incomplete argument: {arg}", file=sys.stderr)
            sys.exit(2)
    return opts


def default_xmux_project_dir() -> str:
    path = os.path.abspath(os.getcwd())
    while path and path != os.path.dirname(path):
        if os.path.exists(os.path.join(path, ".git")):
            return path
        path = os.path.dirname(path)
    return os.path.abspath(os.getcwd())


def default_xmux_state_dir(project_dir: str | None = None) -> str:
    return os.path.join(project_dir or default_xmux_project_dir(), ".codex", "xmux")


def resolve_config_path(opts) -> str:
    if opts["home"] and opts["project"]:
        print("--home and --project are mutually exclusive", file=sys.stderr)
        sys.exit(2)
    if opts["home"]:
        return os.path.join(os.path.expanduser(opts["home"]), "config.toml")
    if opts["project"]:
        return os.path.join(os.path.abspath(opts["project"]), ".codex", "config.toml")
    return os.path.expanduser("~/.codex/config.toml")


def main() -> None:
    opts = parse_args(sys.argv[1:])
    config_path = resolve_config_path(opts)
    script_install_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    xmux_install_dir = os.path.abspath(opts["xmux_install_dir"] or script_install_dir)
    xmux_project_dir = os.path.abspath(opts["xmux_project_dir"] or default_xmux_project_dir())
    xmux_state_dir = os.path.abspath(
        opts["xmux_state_dir"] or default_xmux_state_dir(xmux_project_dir)
    )
    server_path = opts["server_path"] or os.path.join(xmux_install_dir, "xmux-lead-mcp-server.js")

    content = remove_xmux_blocks(read_text(config_path))
    if opts["remove"]:
        remove_local_plugin_cache(config_path)
        write_text(config_path, content + ("\n" if content else ""))
        print(f"[OK] Removed XMux Codex lead config from {config_path}")
        return

    global_config = os.path.expanduser("~/.codex/config.toml")
    if not content.strip() and os.path.abspath(global_config) != os.path.abspath(config_path):
        content = remove_xmux_blocks(read_text(global_config))

    block = build_plugin_block(xmux_install_dir) + "\n" + build_block(
        server_path,
        xmux_install_dir,
        xmux_project_dir,
        xmux_state_dir,
    )
    if content and not content.endswith("\n"):
        content += "\n"
    new_content = content + "\n" + block if content.strip() else block
    write_text(config_path, new_content)
    for cache_path in legacy_plugin_cache_roots(config_path):
        if os.path.islink(cache_path) or os.path.isfile(cache_path):
            os.unlink(cache_path)
        elif os.path.isdir(cache_path):
            shutil.rmtree(cache_path)
    install_local_plugin_cache(config_path, xmux_install_dir)
    print(f"[OK] Wrote {SERVER_NAME} to {config_path}")
    print(f"     server: {server_path}")
    print(f"     xmux_install_dir: {xmux_install_dir}")
    print(f"     xmux_project_dir: {xmux_project_dir}")
    print(f"     xmux_state_dir: {xmux_state_dir}")


if __name__ == "__main__":
    main()
