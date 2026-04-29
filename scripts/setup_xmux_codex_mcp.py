#!/usr/bin/env python3
"""Install, inspect, or remove explicit XMux Codex integration.

This configures Codex as the XMux lead, exposing tools such as
send_to_teammate/read_teammate_response. It is intentionally not part of the
Homebrew install lifecycle; callers must invoke it through an explicit Codex
setup/remove flow.
"""

import os
import shutil
import sys
import tomllib


SERVER_NAME = "xmux_lead"
MARKETPLACE_NAME = "xmux-local"
PLUGIN_KEY = f"xmux@{MARKETPLACE_NAME}"
RULE_BEGIN = "# XMUX_COMMAND_RULE_BEGIN"
RULE_END = "# XMUX_COMMAND_RULE_END"
LEGACY_PREFIX = "a" + "mux"
LEGACY_SERVER_NAMES = (f"{LEGACY_PREFIX}_lead",)
LEGACY_MARKETPLACE_NAMES = (f"{LEGACY_PREFIX}-local",)
LEGACY_PLUGIN_KEYS = (f"{LEGACY_PREFIX}@{LEGACY_PREFIX}-local",)
LOCAL_PLUGIN_CACHE_VERSION = "local"
SKILL_MARKER = ".xmux-managed-skill"


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


def remove_marker_block(content: str, begin: str, end: str) -> str:
    lines = content.split("\n")
    out = []
    skip = False
    for line in lines:
        stripped = line.strip()
        if stripped == begin:
            skip = True
            continue
        if skip and stripped == end:
            skip = False
            continue
        if skip:
            continue
        out.append(line)
    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out)


def build_block(
    server_path: str,
    xmux_install_dir: str,
    xmux_project_dir: str | None = None,
    xmux_state_dir: str | None = None,
) -> str:
    path_env = resolve_path_with_node()
    home = os.path.expanduser("~")
    # Project and state paths are runtime-scoped. They are injected into the
    # Codex lead process by `xmux -n <session>` and inherited by the MCP server.
    # Do not pin them in the global Codex config, otherwise one project's MCP
    # mailbox can leak into every other XMux session.
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
"""


def toml_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def parse_toml_assignment_value(line: str, key: str) -> str | None:
    try:
        parsed = tomllib.loads(f"[section]\n{line}\n")
    except tomllib.TOMLDecodeError:
        return None
    value = parsed.get("section", {}).get(key)
    return value if isinstance(value, str) else None


def path_with_xmux_bin(xmux_install_dir: str, base_path: str | None = None) -> str:
    xmux_bin = os.path.join(os.path.abspath(xmux_install_dir), "bin")
    if base_path is None:
        base_path = resolve_path_with_node()
    parts = [
        part
        for part in base_path.split(":")
        if part and not is_xmux_runtime_bin_path(part, xmux_bin)
    ]
    return ":".join([xmux_bin, *parts])


def is_xmux_runtime_bin_path(path: str, current_xmux_bin: str) -> bool:
    expanded = os.path.abspath(os.path.expanduser(path))
    if expanded == os.path.abspath(current_xmux_bin):
        return True
    if os.path.basename(expanded) != "bin":
        return False
    install_dir = os.path.dirname(expanded)
    if os.path.isfile(os.path.join(install_dir, "xmux.zsh")) and os.path.isfile(
        os.path.join(expanded, "xmux")
    ):
        return True
    if os.path.basename(install_dir) != "libexec":
        return False
    package_dir = os.path.dirname(install_dir)
    parent_dir = os.path.dirname(package_dir)
    return os.path.basename(package_dir) == "xmux" or os.path.basename(parent_dir) == "xmux"


def ensure_codex_shell_environment(content: str, xmux_install_dir: str) -> str:
    install_dir = os.path.abspath(xmux_install_dir)
    lines = content.split("\n")
    header = "[shell_environment_policy.set]"

    start = None
    for idx, line in enumerate(lines):
        if line.strip() == header:
            start = idx
            break

    if start is None:
        block = "\n".join(
            [
                header,
                f"PATH = {toml_quote(path_with_xmux_bin(install_dir))}",
                f"XMUX_INSTALL_DIR = {toml_quote(install_dir)}",
            ]
        )
        if content.strip():
            return content.rstrip() + "\n\n" + block + "\n"
        return block + "\n"

    end = len(lines)
    for idx in range(start + 1, len(lines)):
        stripped = lines[idx].strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            end = idx
            break

    seen_path = False
    seen_install = False
    for idx in range(start + 1, end):
        stripped = lines[idx].strip()
        key = stripped.split("=", 1)[0].strip() if "=" in stripped else ""
        if key == "PATH":
            current = parse_toml_assignment_value(stripped, "PATH")
            base = current if current is not None else resolve_path_with_node()
            lines[idx] = f"PATH = {toml_quote(path_with_xmux_bin(install_dir, base))}"
            seen_path = True
        elif key == "XMUX_INSTALL_DIR":
            lines[idx] = f"XMUX_INSTALL_DIR = {toml_quote(install_dir)}"
            seen_install = True

    insert_at = start + 1
    inserts = []
    if not seen_path:
        inserts.append(f"PATH = {toml_quote(path_with_xmux_bin(install_dir))}")
    if not seen_install:
        inserts.append(f"XMUX_INSTALL_DIR = {toml_quote(install_dir)}")
    if inserts:
        lines[insert_at:insert_at] = inserts

    return "\n".join(lines).rstrip() + "\n"


def remove_codex_shell_environment(content: str, xmux_install_dir: str) -> str:
    lines = content.split("\n")
    header = "[shell_environment_policy.set]"
    install_bin = os.path.join(os.path.abspath(xmux_install_dir), "bin")

    start = None
    for idx, line in enumerate(lines):
        if line.strip() == header:
            start = idx
            break
    if start is None:
        return content

    end = len(lines)
    for idx in range(start + 1, len(lines)):
        stripped = lines[idx].strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            end = idx
            break

    section_lines = []
    for line in lines[start + 1 : end]:
        stripped = line.strip()
        key = stripped.split("=", 1)[0].strip() if "=" in stripped else ""
        if key == "XMUX_INSTALL_DIR":
            continue
        if key == "PATH":
            current = parse_toml_assignment_value(stripped, "PATH")
            if current is not None:
                parts = [
                    part
                    for part in current.split(":")
                    if part and not is_xmux_runtime_bin_path(part, install_bin)
                ]
                if parts:
                    section_lines.append(f"PATH = {toml_quote(':'.join(parts))}")
                continue
        section_lines.append(line)

    if any(line.strip() for line in section_lines):
        lines[start + 1 : end] = section_lines
    else:
        lines[start:end] = []

    while lines and lines[-1].strip() == "":
        lines.pop()
    return "\n".join(lines) + ("\n" if lines else "")


def plugin_cache_root(config_path: str) -> str:
    return os.path.join(codex_home(config_path), "plugins", "cache", MARKETPLACE_NAME, "xmux")


def plugin_cache_path(config_path: str) -> str:
    return os.path.join(plugin_cache_root(config_path), LOCAL_PLUGIN_CACHE_VERSION)


def remove_local_plugin_cache(config_path: str) -> None:
    home = codex_home(config_path)
    for cache_path in (
        plugin_cache_root(config_path),
        *legacy_plugin_cache_roots(config_path),
    ):
        if os.path.islink(cache_path) or os.path.isfile(cache_path):
            os.unlink(cache_path)
        elif os.path.isdir(cache_path):
            shutil.rmtree(cache_path)
        parent = os.path.dirname(cache_path)
        while os.path.abspath(parent) != home and os.path.abspath(parent).startswith(home):
            try:
                os.rmdir(parent)
            except OSError:
                break
            parent = os.path.dirname(parent)


def rules_path(config_path: str) -> str:
    codex_home = os.path.dirname(os.path.abspath(config_path))
    return os.path.join(codex_home, "rules", "default.rules")


def install_xmux_command_rule(config_path: str) -> None:
    path = rules_path(config_path)
    content = remove_marker_block(read_text(path), RULE_BEGIN, RULE_END)
    block = "\n".join(
        [
            RULE_BEGIN,
            "# Allow the scoped XMux wrapper command; XMux skills still control operation scope.",
            'prefix_rule(pattern=["xmux"], decision="allow")',
            RULE_END,
        ]
    )
    if content.strip():
        content = content.rstrip() + "\n\n" + block + "\n"
    else:
        content = block + "\n"
    write_text(path, content)


def remove_xmux_command_rule(config_path: str) -> None:
    path = rules_path(config_path)
    content = remove_marker_block(read_text(path), RULE_BEGIN, RULE_END)
    write_text(path, content + ("\n" if content else ""))


def legacy_plugin_cache_roots(config_path: str) -> tuple[str, ...]:
    return tuple(
        os.path.join(codex_home(config_path), "plugins", "cache", marketplace, LEGACY_PREFIX)
        for marketplace in LEGACY_MARKETPLACE_NAMES
    )


def codex_home(config_path: str) -> str:
    return os.path.dirname(os.path.abspath(config_path))


def skills_root(config_path: str) -> str:
    return os.path.join(codex_home(config_path), "skills")


def skill_source_dirs(xmux_install_dir: str, skills_dir: str = "") -> tuple[str, ...]:
    candidates = []
    if skills_dir:
        candidates.append(os.path.expanduser(skills_dir))
    env_source = os.environ.get("XMUX_CODEX_SKILLS_DIR")
    if env_source:
        candidates.append(os.path.expanduser(env_source))

    seen = set()
    out = []
    for candidate in candidates:
        path = os.path.abspath(candidate)
        if path in seen:
            continue
        seen.add(path)
        out.append(path)
    return tuple(out)


def xmux_skill_sources(xmux_install_dir: str, skills_dir: str = "") -> list[tuple[str, str]]:
    sources: dict[str, str] = {}
    for base in skill_source_dirs(xmux_install_dir, skills_dir):
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if not name.startswith("xmux-") or name in sources:
                continue
            source = os.path.join(base, name)
            if os.path.isfile(os.path.join(source, "SKILL.md")):
                sources[name] = source
    return [(name, sources[name]) for name in sorted(sources)]


def is_xmux_managed_skill(path: str) -> bool:
    return os.path.isdir(path) and os.path.isfile(os.path.join(path, SKILL_MARKER))


def install_xmux_skills(
    config_path: str,
    xmux_install_dir: str,
    skills_dir: str = "",
) -> list[str]:
    root = skills_root(config_path)
    installed = []
    for name, source in xmux_skill_sources(xmux_install_dir, skills_dir):
        dst = os.path.join(root, name)
        if os.path.exists(dst) and not is_xmux_managed_skill(dst):
            continue
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        elif os.path.islink(dst) or os.path.isfile(dst):
            os.unlink(dst)
        os.makedirs(root, exist_ok=True)
        shutil.copytree(source, dst)
        write_text(os.path.join(dst, SKILL_MARKER), os.path.abspath(source) + "\n")
        installed.append(name)
    return installed


def remove_xmux_skills(config_path: str) -> list[str]:
    root = skills_root(config_path)
    removed = []
    if not os.path.isdir(root):
        return removed
    for name in sorted(os.listdir(root)):
        if not name.startswith("xmux-"):
            continue
        path = os.path.join(root, name)
        if not is_xmux_managed_skill(path):
            continue
        shutil.rmtree(path)
        removed.append(name)
    return removed


def _content_has_xmux_mcp(content: str, server_path: str, xmux_install_dir: str) -> bool:
    return (
        f"[mcp_servers.{SERVER_NAME}]" in content
        and f'args = ["{server_path}"]' in content
        and f'XMUX_INSTALL_DIR = "{os.path.abspath(xmux_install_dir)}"' in content
        and "XMUX_PROJECT_DIR =" not in content
        and "XMUX_STATE_DIR =" not in content
    )


def _content_has_shell_environment(content: str, xmux_install_dir: str) -> bool:
    install_bin = os.path.join(os.path.abspath(xmux_install_dir), "bin")
    return (
        "[shell_environment_policy.set]" in content
        and f'XMUX_INSTALL_DIR = "{os.path.abspath(xmux_install_dir)}"' in content
        and install_bin in content
    )


def _rules_have_xmux_command(config_path: str) -> bool:
    content = read_text(rules_path(config_path))
    return (
        RULE_BEGIN in content
        and RULE_END in content
        and 'prefix_rule(pattern=["xmux"], decision="allow")' in content
    )


def _installed_skill_names(config_path: str) -> set[str]:
    root = skills_root(config_path)
    if not os.path.isdir(root):
        return set()
    return {
        name
        for name in os.listdir(root)
        if name.startswith("xmux-")
        and os.path.isfile(os.path.join(root, name, "SKILL.md"))
        and is_xmux_managed_skill(os.path.join(root, name))
    }


def doctor_codex(
    config_path: str,
    xmux_install_dir: str,
    server_path: str,
    skills_dir: str = "",
    quiet: bool = False,
) -> int:
    content = read_text(config_path)
    issues: list[str] = []
    notes: list[tuple[str, str]] = []

    if not os.path.isfile(config_path):
        issues.append(f"missing config: {config_path}")
    elif _content_has_xmux_mcp(content, server_path, xmux_install_dir):
        notes.append(("OK", f"mcp server points at {server_path}"))
    else:
        issues.append("xmux_lead MCP config is missing or stale")

    if _content_has_shell_environment(content, xmux_install_dir):
        notes.append(("OK", "Codex shell PATH includes XMux bin"))
    else:
        issues.append("Codex shell PATH/XMUX_INSTALL_DIR setup is missing or stale")

    if _rules_have_xmux_command(config_path):
        notes.append(("OK", f"scoped xmux command rule exists in {rules_path(config_path)}"))
    else:
        issues.append("scoped xmux command rule is missing")

    source_names = {name for name, _ in xmux_skill_sources(xmux_install_dir, skills_dir)}
    installed_names = _installed_skill_names(config_path)
    if source_names:
        missing = sorted(source_names - installed_names)
        if missing:
            issues.append("missing XMux Codex skills: " + ", ".join(missing))
        else:
            notes.append(("OK", f"XMux Codex skills installed under {skills_root(config_path)}"))
    else:
        notes.append(
            (
                "WARN",
                "no XMux skill source directory found; pass --skills-dir or set XMUX_CODEX_SKILLS_DIR",
            )
        )

    if os.path.exists(plugin_cache_path(config_path)):
        notes.append(("WARN", "legacy XMux plugin cache is present; run xmux setup-codex to remove it"))
    else:
        notes.append(("OK", "legacy XMux plugin cache is absent"))

    if quiet:
        return 1 if issues else 0

    if issues:
        print("[FAIL] XMux Codex setup is incomplete")
        for issue in issues:
            print(f"  - {issue}")
        for level, note in notes:
            print(f"  - [{level}] {note}")
        print("Run: xmux setup-codex")
        return 1

    print("[OK] XMux Codex setup looks ready")
    for level, note in notes:
        print(f"  - [{level}] {note}")
    return 0


def parse_args(argv):
    opts = {
        "remove": False,
        "doctor": False,
        "quiet": False,
        "install_skills": True,
        "skills_dir": "",
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
        elif arg == "--doctor":
            opts["doctor"] = True
            i += 1
        elif arg == "--quiet":
            opts["quiet"] = True
            i += 1
        elif arg == "--without-skills":
            opts["install_skills"] = False
            i += 1
        elif arg == "--skills-dir" and i + 1 < len(argv):
            opts["skills_dir"] = os.path.expanduser(argv[i + 1])
            i += 2
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

    if opts["doctor"]:
        raise SystemExit(
            doctor_codex(
                config_path,
                xmux_install_dir,
                server_path,
                skills_dir=opts["skills_dir"],
                quiet=opts["quiet"],
            )
        )

    content = remove_xmux_blocks(read_text(config_path))
    if opts["remove"]:
        content = remove_codex_shell_environment(content, xmux_install_dir)
        remove_local_plugin_cache(config_path)
        remove_xmux_command_rule(config_path)
        removed_skills = remove_xmux_skills(config_path)
        write_text(config_path, content + ("\n" if content else ""))
        print(f"[OK] Removed XMux Codex lead config from {config_path}")
        if removed_skills:
            print(f"     removed skills: {', '.join(removed_skills)}")
        return

    global_config = os.path.expanduser("~/.codex/config.toml")
    if (
        opts["project"]
        and not content.strip()
        and os.path.abspath(global_config) != os.path.abspath(config_path)
    ):
        content = remove_xmux_blocks(read_text(global_config))

    content = ensure_codex_shell_environment(content, xmux_install_dir)

    block = build_block(
        server_path,
        xmux_install_dir,
        xmux_project_dir,
        xmux_state_dir,
    )
    if content and not content.endswith("\n"):
        content += "\n"
    new_content = content + "\n" + block if content.strip() else block
    write_text(config_path, new_content)
    remove_local_plugin_cache(config_path)
    installed_skills = []
    if opts["install_skills"]:
        installed_skills = install_xmux_skills(
            config_path,
            xmux_install_dir,
            opts["skills_dir"],
        )
    install_xmux_command_rule(config_path)
    print(f"[OK] Wrote {SERVER_NAME} to {config_path}")
    print(f"     server: {server_path}")
    print(f"     xmux_install_dir: {xmux_install_dir}")
    print("     xmux_project_dir: inherited from xmux-launched Codex runtime")
    print("     xmux_state_dir: inherited from xmux-launched Codex runtime")
    if installed_skills:
        print(f"     skills: {', '.join(installed_skills)}")
    elif opts["install_skills"]:
        print("     skills: skipped; pass --skills-dir or set XMUX_CODEX_SKILLS_DIR")
    print("     plugin_cache: disabled; stale XMux plugin cache removed if present")


if __name__ == "__main__":
    main()
