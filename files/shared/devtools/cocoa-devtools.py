#!/usr/bin/env python3
"""Local Cocoa control plane for API checks, worktrees, and safe releases."""

from __future__ import annotations

import errno
import hashlib
import http.server
import json
import os
import re
import shlex
import shutil
import socketserver
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse


PORT = 7777
HERE = Path(__file__).resolve().parent
HTML = HERE / "cocoa-reference.html"
CONFIG_PATH = os.environ.get(
    "TRIANGULATE_CONFIG", str(Path.home() / ".claude/triangulate.conf")
)
STATE_PATH = os.environ.get(
    "COCOA_DEVTOOLS_STATE",
    str(Path.home() / ".local/state/cocoa-devtools/triangulations.json"),
)
STATE_LOCK = threading.Lock()
ROLE_BASES = {"back": "dev", "front": "dev", "app": "dev"}
REQUIRED_ROLES = {"back", "front", "app"}
VERIFY_COMMANDS: dict[str, tuple[str, list[str]]] = {
    "back": ("functions", ["bash", "-c", "npm run typecheck && npm run format:check && npm run lint && npm run test:unit"]),
    "front": (".", ["npm", "run", "check:all"]),
    "app": (".", ["bash", "-c", "flutter analyze && flutter test"]),
}
ALLOWED_ORIGINS = {
    f"http://localhost:{PORT}",
    f"http://127.0.0.1:{PORT}",
}
ALLOWED_FIREBASE_PROJECTS = {
    "cocoa-dev-v2",
    "cocoa-test-v2",
    "cocoa-pro-v2-acd2c",
}

STATIC_COMMANDS = {
    "ios-dev": ["bash", "scripts/testflight.sh", "dev"],
    "ios-staging": ["bash", "scripts/testflight.sh", "staging"],
    "ios-prod": ["bash", "scripts/testflight.sh", "prod"],
    "aab-dev": [
        "flutter", "build", "appbundle", "--flavor", "dev",
        "-t", "lib/main_dev.dart", "--release",
    ],
    "aab-staging": [
        "flutter", "build", "appbundle", "--flavor", "staging",
        "-t", "lib/main_staging.dart", "--release",
    ],
    "aab-prod": [
        "flutter", "build", "appbundle", "--flavor", "prod",
        "-t", "lib/main_prod.dart", "--release",
    ],
    "flutter-test": ["flutter", "test"],
    "flutter-analyze": ["flutter", "analyze"],
    "flutter-pub-get": ["flutter", "pub", "get"],
    "flutter-clean": ["bash", "-c", "flutter clean && flutter pub get"],
    "git-status": ["git", "status", "--short", "--branch"],
    "git-log": ["git", "log", "--oneline", "-15"],
    "git-push": ["git", "push", "-u", "origin", "HEAD"],
    "check-builds": [
        "bash", "-c",
        "pgrep -fl 'xcodebuild|flutter_tools.snapshot' || echo 'Sin builds vivos.'",
    ],
    "kill-builds": [
        "bash", "-c",
        "pkill -f xcodebuild 2>/dev/null; "
        "pkill -f flutter_tools 2>/dev/null; echo 'Listo — procesos terminados.'",
    ],
    "open-project": ["open", "."],
    "open-aab-dev": [
        "bash", "-c",
        "open build/app/outputs/bundle/devRelease/ 2>/dev/null "
        "|| echo 'No existe todavía. Ejecuta el build primero.'",
    ],
    "open-aab-staging": [
        "bash", "-c",
        "open build/app/outputs/bundle/stagingRelease/ 2>/dev/null "
        "|| echo 'No existe todavía. Ejecuta el build primero.'",
    ],
    "open-aab-prod": [
        "bash", "-c",
        "open build/app/outputs/bundle/prodRelease/ 2>/dev/null "
        "|| echo 'No existe todavía. Ejecuta el build primero.'",
    ],
    "check-asc-env": [
        "bash", "-c",
        "[ -f ios/.asc.env ] && echo '✅ ios/.asc.env existe.' "
        "|| echo '❌ Falta ios/.asc.env'",
    ],
    "check-firebase-pins": [
        "bash", "-c",
        r"grep -E 'firebase|cloud_firestore' pubspec.yaml "
        r"| grep -v '^\s*#' | grep -v '\^' "
        r"&& echo '⚠ Encontrado sin caret — revisar' || echo '✅ Todos con caret.'",
    ],
}


def set_config_path(path: str) -> None:
    """Override the repository registry (used by tests and managed launchers)."""
    global CONFIG_PATH
    CONFIG_PATH = path


def set_state_path(path: str) -> None:
    """Override the durable closed-triangulation registry (used by tests)."""
    global STATE_PATH
    STATE_PATH = path


def _read_archive_state_unlocked() -> dict[str, object]:
    path = Path(STATE_PATH).expanduser()
    if not path.is_file():
        return {"version": 1, "archived": {}}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ValueError(f"no se pudo leer el registro durable {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ValueError(
            f"el registro durable {path} contiene JSON inválido; no se modificó"
        ) from error
    if not isinstance(value, dict) or value.get("version") != 1:
        raise ValueError(f"el registro durable {path} tiene un formato o versión no compatible")
    archived = value.get("archived")
    if not isinstance(archived, dict):
        raise ValueError(f"el registro durable {path} tiene una sección archived inválida")
    return {"version": 1, "archived": archived}


def load_archive_state() -> dict[str, object]:
    with STATE_LOCK:
        return _read_archive_state_unlocked()


def set_triangulation_archived(slug: str, evidence: str, archived: bool = True, *, _verified=None) -> dict[str, object]:
    """Persist an operator receipt without deleting branches or worktrees."""
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", slug):
        raise ValueError("slug de triangulación inválido")
    evidence = evidence.strip()
    if archived and not evidence:
        raise ValueError("se requiere evidencia de cierre (PR, commit o recibo QA)")
    # Validate before taking the registry lock; never accept caller-supplied PASS.
    load_archive_state()
    closure = verify_closure(slug, _verified=_verified) if archived else None
    if closure is not None and closure["state"] != "PASS":
        raise ValueError(json.dumps(closure, ensure_ascii=False))
    with STATE_LOCK:
        state = _read_archive_state_unlocked()
        entries = state["archived"]
        assert isinstance(entries, dict)
        if archived:
            receipt: dict[str, object] = {
                "slug": slug,
                "status": "archived",
                "archived_at": datetime.now(timezone.utc).isoformat(),
                "evidence": evidence[:4000],
                "closure": closure,
            }
            entries[slug] = receipt
        else:
            previous = entries.pop(slug, None)
            receipt = {
                "slug": slug,
                "status": "restored",
                "evidence": previous.get("evidence", "") if isinstance(previous, dict) else "",
            }
        path = Path(STATE_PATH).expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, path)
        return receipt


def verify_closure(slug: str, *, _verified=None) -> dict[str, object]:
    """Closure gate. No remote writes or commands from receipts; fixed final suites."""
    def unique(pairs):
        obj = {}
        for key, value in pairs:
            if key in obj:
                raise ValueError("duplicate evidence field")
            obj[key] = value
        return obj
    result: dict[str, object] = {"state": "UNVERIFIED", "slug": slug, "repos": []}
    try:
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", slug):
            raise ValueError("invalid slug")
        repos = load_repo_config()
        if set(repos) != REQUIRED_ROLES or len(set(repos.values())) != 3:
            raise ValueError("three distinct repository owners required")
        source_hook = HERE.parent.parent / "claude/hooks/triangulate-handoff.sh"
        hook = source_hook if source_hook.is_file() else Path.home()/".claude/hooks/triangulate-handoff.sh"
        snapshots = []
        for role in ("back", "front", "app"):
            cwd = str(Path(repos[role])/".claude/worktrees"/f"triangulate-{slug}")
            validate_push(cwd)
            head = _git(cwd, "rev-parse", "HEAD")
            # Fetch no refs: query the provider directly and require the observed object locally.
            remote = subprocess.run(["git", "ls-remote", "--exit-code", "origin", "refs/heads/dev"],
                cwd=cwd, capture_output=True, text=True, timeout=30, check=True)
            dev = remote.stdout.split()[0]
            branch = _git(cwd, "branch", "--show-current")
            pushed = subprocess.run(["git", "ls-remote", "--exit-code", "origin", f"refs/heads/{branch}"],
                cwd=cwd, capture_output=True, text=True, timeout=30, check=True)
            if pushed.stdout.split()[0] != head:
                raise ValueError(f"{role}: branch not pushed at candidate revision")
            if not re.fullmatch(r"[a-f0-9]{40,64}", dev):
                raise ValueError(f"{role}: invalid remote dev identity")
            _git(cwd, "merge-base", "--is-ancestor", head, dev)
            probe = subprocess.run(["bash", str(hook), "--verify"], cwd=cwd,
                env={**os.environ, "CLAUDE_PROJECT_DIR": cwd, "TRIANGULATE_CONFIG": CONFIG_PATH},
                capture_output=True, text=True, timeout=60)
            if probe.returncode:
                raise ValueError(f"{role}: recovery not verified; native owner must repair it")
            match = re.search(r"RECOVERY DATA (.+)/recovery/" + role + r"\.json \(recorded;", probe.stdout)
            if not match:
                raise ValueError(f"{role}: missing verified authority pointer")
            authority = Path(match[1])
            checkpoint = authority/"recovery"/f"{role}.json"
            raw = checkpoint.read_bytes()
            if len(raw) > 8192:
                raise ValueError("oversized checkpoint")
            data = json.loads(raw, object_pairs_hook=unique)
            if (data["revision"] != head or data["coordination"] != {"phase":"validated", "wait":{}}
                    or data["blocker"]["kind"] != "none" or data["pending_delivery"]):
                raise ValueError(f"{role}: unfinished work/wait is not closure, regardless of owner")
            # Canonical planning must be tracked and clean, not merely present on disk.
            back = str(Path(repos["back"])/".claude/worktrees"/f"triangulate-{slug}")
            for name in ["state.yaml", *data["artifact_hashes"]]:
                artifact = str((authority/name).relative_to(back))
                _git(back, "ls-files", "--error-unmatch", "--", artifact)
            # A structured receipt, not prose or a PR number, binds required QA evidence.
            for pointer in data["receipts"]:
                path = Path(pointer["path"])
                payload = path.read_bytes()
                if len(payload) > 65536:
                    raise ValueError("oversized repository receipt")
                receipt = json.loads(payload, object_pairs_hook=unique)
                if (set(receipt) != {"role", "revision", "status", "remaining", "checks"}
                        or receipt["role"] != role or receipt["revision"] != head
                        or receipt["status"] != "complete" or receipt["remaining"] != []
                        or not isinstance(receipt["checks"], list) or not receipt["checks"]):
                    raise ValueError(f"{role}: contradictory/incomplete receipt")
                required = {"functional", "contract"} | ({"device"} if role == "app" else set())
                names = [check["name"] for check in receipt["checks"]]
                if not required.issubset(names) or len(names) != len(set(names)):
                    raise ValueError(f"{role}: missing/duplicate required QA evidence")
                for check in receipt["checks"]:
                    if (set(check) != {"name", "state", "revision", "path", "sha256"}
                            or not check["name"] or check["state"] != "PASS" or check["revision"] != head):
                        raise ValueError(f"{role}: missing, stale or failed required check")
                    evidence_path = Path(check["path"]).resolve(strict=True)
                    if not evidence_path.is_relative_to(Path(cwd).resolve()):
                        raise ValueError("evidence outside owning worktree")
                    if not evidence_path.is_file():
                        raise ValueError("nonregular check evidence")
                    with evidence_path.open("rb") as source:
                        evidence_bytes = source.read(4 * 1024 * 1024 + 1)
                    if len(evidence_bytes) > 4 * 1024 * 1024:
                        raise ValueError("oversized check evidence")
                    if hashlib.sha256(evidence_bytes).hexdigest() != check["sha256"]:
                        raise ValueError("evidence changed")
                    snapshots.append((evidence_path, evidence_bytes))
                snapshots.append((path, payload))
            snapshots.append((checkpoint, raw))
            result["repos"].append({"role":role, "cwd":cwd, "head":head, "dev":dev})
        # Only server-produced results from this promotion operation may be reused.
        # HTTP callers cannot provide _verified; ordinary archival executes final suites.
        for item in result["repos"]:
            verification = (_verified or {}).get(item["role"])
            if verification is None:
                verification = verify_worktree(item["cwd"], item["role"])
            if (verification.get("state") != "PASS" or verification.get("executed") is not True
                    or verification.get("returncode") != 0 or verification.get("tested_revision") != item["head"]):
                raise ValueError(f"{item['role']}: final functional verification failed/stale")
            item["verification"] = verification
        # Revalidate after all provider/receipt reads, before recording any closure.
        for item in result["repos"]:
            validate_push(item["cwd"])
            if _git(item["cwd"], "rev-parse", "HEAD") != item["head"]:
                raise ValueError("candidate changed during closure")
        if any(path.read_bytes() != raw for path, raw in snapshots):
            raise ValueError("recovery evidence changed during closure")
        result["state"] = "PASS"
    except (OSError, subprocess.SubprocessError) as error:
        result["reason"] = str(error)[:1000]  # inaccessible is UNVERIFIED, never PASS
    except (ValueError, KeyError, TypeError, IndexError) as error:
        result.update(state="BLOCKED", reason=str(error)[:1000])
    return result


def _git(cwd: str, *args: str, check: bool = True) -> str:
    proc = subprocess.run(
        ["git", *args], cwd=cwd, text=True, capture_output=True, check=False
    )
    if proc.returncode:
        if check:
            raise subprocess.CalledProcessError(
                proc.returncode, proc.args, output=proc.stdout, stderr=proc.stderr
            )
        return ""
    return proc.stdout.strip()


def load_repo_config(path: str | None = None) -> dict[str, str]:
    config = Path(path or CONFIG_PATH).expanduser()
    repos: dict[str, str] = {}
    if not config.is_file():
        return repos
    for raw in config.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        role, value = line.split("=", 1)
        if role in ROLE_BASES and value.strip():
            repos[role] = str(Path(value.strip()).expanduser().resolve())
    return repos


def repo_path(role: str, path: str | None = None) -> str:
    """Obtiene la ruta configurada para un repositorio por rol."""
    repo = load_repo_config(path).get(role)
    if not repo:
        raise ValueError(f"no hay repositorio configurado para el rol {role}")
    return repo


def _firebase_command(cwd: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["firebase", *args],
        cwd=cwd,
        text=True,
        capture_output=True,
        timeout=60,
        env=runtime_env(),
        check=False,
    )


def _index_signature(index: object) -> tuple[str, str, tuple[tuple[str, str], ...]] | None:
    if not isinstance(index, dict):
        return None
    collection_group = index.get("collectionGroup")
    if not isinstance(collection_group, str):
        return None
    fields = index.get("fields")
    if not isinstance(fields, list):
        return None
    summarized_fields: list[tuple[str, str]] = []
    for field in fields:
        if not isinstance(field, dict) or not isinstance(field.get("fieldPath"), str):
            return None
        mode = next(
            (
                str(field[key])
                for key in ("order", "arrayConfig", "vectorConfig")
                if key in field
            ),
            "",
        )
        summarized_fields.append((str(field["fieldPath"]), mode))
    query_scope = str(index.get("queryScope") or "COLLECTION")
    return collection_group, query_scope, tuple(summarized_fields)


def _summarize_index(index: object) -> dict[str, object]:
    signature = _index_signature(index)
    if signature is None:
        return {"collectionGroup": "?", "fields": []}
    collection_group, _query_scope, fields = signature
    return {
        "collectionGroup": collection_group,
        "fields": [f"{path}:{mode}" if mode else path for path, mode in fields],
    }


def _normalized_rules(content: str) -> bytes:
    normalized = "\n".join(line.rstrip() for line in content.splitlines())
    return normalized.encode("utf-8")


def check_env_parity(cwd: str, project: str) -> dict[str, object]:
    """Compara índices y reglas locales del backend con Firebase sin bloquear."""
    result: dict[str, object] = {
        "project": project,
        "missing_indexes": [],
        "rules_in_sync": False,
        "errors": [],
        "source": "origin/dev",
    }
    errors = result["errors"]
    assert isinstance(errors, list)

    try:
        fetch_process = subprocess.run(
            ["git", "-C", cwd, "fetch", "origin", "dev", "--quiet"],
            text=True,
            capture_output=True,
            check=False,
        )
        if fetch_process.returncode:
            detail = (fetch_process.stderr or fetch_process.stdout).strip()
            errors.append(
                f"git fetch origin dev falló ({fetch_process.returncode}): {detail}"
            )
    except OSError as error:
        errors.append(f"no se pudo ejecutar git fetch origin dev: {error}")

    local_indexes: list[object] | None = None
    indexes_path = Path(cwd) / "firestore.indexes.json"
    try:
        try:
            indexes_process = subprocess.run(
                ["git", "-C", cwd, "show", "origin/dev:firestore.indexes.json"],
                text=True,
                capture_output=True,
                check=False,
            )
        except OSError as error:
            errors.append(
                f"no se pudo ejecutar git show origin/dev:firestore.indexes.json: {error}"
            )
            result["source"] = "working-tree-fallback"
            indexes_content = indexes_path.read_text(encoding="utf-8")
        else:
            if indexes_process.returncode:
                detail = (indexes_process.stderr or indexes_process.stdout).strip()
                errors.append(
                    "git show origin/dev:firestore.indexes.json falló "
                    f"({indexes_process.returncode}): {detail}"
                )
                result["source"] = "working-tree-fallback"
                indexes_content = indexes_path.read_text(encoding="utf-8")
            else:
                indexes_content = indexes_process.stdout
        indexes_document = json.loads(indexes_content)
        if not isinstance(indexes_document, dict) or not isinstance(
            indexes_document.get("indexes"), list
        ):
            raise ValueError("el documento no contiene una lista indexes")
        local_indexes = indexes_document["indexes"]
    except (OSError, ValueError, json.JSONDecodeError) as error:
        errors.append(f"no se pudieron leer los índices locales: {error}")

    try:
        deployed_process = _firebase_command(
            cwd, "firestore:indexes", "--project", project
        )
        if deployed_process.returncode:
            detail = (deployed_process.stderr or deployed_process.stdout).strip()
            errors.append(
                f"firebase firestore:indexes falló ({deployed_process.returncode}): {detail}"
            )
        elif local_indexes is not None:
            deployed_document = json.loads(deployed_process.stdout)
            if isinstance(deployed_document, dict) and isinstance(
                deployed_document.get("result"), dict
            ):
                deployed_document = deployed_document["result"]
            if not isinstance(deployed_document, dict) or not isinstance(
                deployed_document.get("indexes"), list
            ):
                raise ValueError("la respuesta no contiene una lista indexes")
            deployed_signatures = {
                signature
                for item in deployed_document["indexes"]
                if (signature := _index_signature(item)) is not None
            }
            result["missing_indexes"] = [
                _summarize_index(item)
                for item in local_indexes
                if _index_signature(item) not in deployed_signatures
            ]
    except subprocess.TimeoutExpired:
        errors.append("firebase firestore:indexes superó el timeout de 60s")
    except OSError as error:
        errors.append(f"no se pudo ejecutar firebase firestore:indexes: {error}")
    except (ValueError, json.JSONDecodeError) as error:
        errors.append(f"no se pudieron interpretar los índices desplegados: {error}")

    rules_path = Path(cwd) / "firestore.rules"
    local_rules_hash: str | None = None
    try:
        try:
            rules_process = subprocess.run(
                ["git", "-C", cwd, "show", "origin/dev:firestore.rules"],
                text=True,
                capture_output=True,
                check=False,
            )
        except OSError as error:
            errors.append(
                f"no se pudo ejecutar git show origin/dev:firestore.rules: {error}"
            )
            result["source"] = "working-tree-fallback"
            rules_content = rules_path.read_text(encoding="utf-8")
        else:
            if rules_process.returncode:
                detail = (rules_process.stderr or rules_process.stdout).strip()
                errors.append(
                    "git show origin/dev:firestore.rules falló "
                    f"({rules_process.returncode}): {detail}"
                )
                result["source"] = "working-tree-fallback"
                rules_content = rules_path.read_text(encoding="utf-8")
            else:
                rules_content = rules_process.stdout
        local_rules_hash = hashlib.sha256(
            _normalized_rules(rules_content)
        ).hexdigest()
    except OSError as error:
        errors.append(f"no se pudieron leer las reglas locales: {error}")

    rules_parity_error = (
        "rules parity: firebase-tools 15.24 no expone lectura de rules; "
        "verificar manualmente antes de un deploy a este ambiente "
        "(doc firestore.md desactualizada)"
    )
    firebase_token = os.environ.get("FIREBASE_TOKEN")
    application_credentials = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not firebase_token and not application_credentials:
        result["rules_in_sync"] = None
        errors.append(rules_parity_error)
    else:
        try:
            access_token = firebase_token
            if not access_token:
                token_process = subprocess.run(
                    ["gcloud", "auth", "application-default", "print-access-token"],
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                if token_process.returncode:
                    raise OSError(token_process.stderr.strip())
                access_token = token_process.stdout.strip()
            if not access_token:
                raise ValueError("no se pudo obtener un access token")

            headers = {"Authorization": f"Bearer {access_token}"}
            releases_url = (
                "https://firebasesecurity.googleapis.com/v1/projects/"
                f"{project}/releases"
            )
            with urllib.request.urlopen(
                urllib.request.Request(releases_url, headers=headers), timeout=30
            ) as response:
                releases_document = json.load(response)
            releases = releases_document.get("releases", [])
            firestore_release = next(
                release
                for release in releases
                if release.get("name", "").endswith("/releases/cloud.firestore")
            )
            ruleset_name = firestore_release["rulesetName"]
            ruleset_url = (
                "https://firebasesecurity.googleapis.com/v1/" f"{ruleset_name}"
            )
            with urllib.request.urlopen(
                urllib.request.Request(ruleset_url, headers=headers), timeout=30
            ) as response:
                ruleset_document = json.load(response)
            deployed_files = ruleset_document["source"]["files"]
            deployed_rules = next(
                item["content"]
                for item in deployed_files
                if item.get("name") == "firestore.rules"
            )
            if local_rules_hash is not None:
                deployed_rules_hash = hashlib.sha256(
                    _normalized_rules(deployed_rules)
                ).hexdigest()
                result["rules_in_sync"] = local_rules_hash == deployed_rules_hash
        except (
            AttributeError,
            KeyError,
            StopIteration,
            OSError,
            TypeError,
            ValueError,
            json.JSONDecodeError,
            subprocess.TimeoutExpired,
            urllib.error.URLError,
        ):
            result["rules_in_sync"] = None
            errors.append(rules_parity_error)

    return result


def _ref_exists(cwd: str, ref: str) -> bool:
    return subprocess.run(
        ["git", "show-ref", "--verify", "--quiet", f"refs/remotes/{ref}"],
        cwd=cwd,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


def resolve_base_ref(cwd: str, role: str | None = None) -> str:
    preferred = ROLE_BASES.get(role or "", "dev")
    candidate = f"origin/{preferred}"
    # The workflow is deliberately dev-only. Returning the required ref even
    # when it is absent makes the configuration error visible; silently using
    # main would create work against the wrong integration line.
    return candidate


def _count(cwd: str, revision: str) -> int:
    output = _git(cwd, "rev-list", "--count", revision, check=False)
    return int(output) if output.isdigit() else 0


def _upstream(cwd: str, branch: str, base_ref: str) -> str:
    upstream = _git(cwd, "rev-parse", "--abbrev-ref", "@{upstream}", check=False)
    if upstream:
        return upstream
    same_name = f"origin/{branch}"
    if branch and _ref_exists(cwd, same_name):
        return same_name
    return base_ref


def _slug(path: str, branch: str) -> str | None:
    marker = "/.claude/worktrees/triangulate-"
    if marker in path:
        return path.split(marker, 1)[1].split("/", 1)[0]
    if branch.startswith("triangulate/"):
        return branch.split("/", 1)[1]
    return None


def _worktree_status(worktree: dict[str, object]) -> None:
    cwd = str(worktree["path"])
    role = str(worktree["role"])
    branch = str(worktree.get("branch") or "")
    base_ref = resolve_base_ref(cwd, role)
    porcelain = _git(cwd, "status", "--porcelain", check=False)
    dirty = len(porcelain.splitlines()) if porcelain else 0
    upstream = _upstream(cwd, branch, base_ref) if branch != "(detached)" else ""
    unpushed = _count(cwd, f"{upstream}..HEAD") if upstream else 0
    commit_epoch = _git(cwd, "log", "-1", "--format=%ct", check=False)

    worktree.update(
        {
            "slug": _slug(cwd, branch),
            "base_ref": base_ref,
            "upstream": upstream or None,
            "dirty": dirty,
            "unpushed": unpushed,
            "ahead_base": _count(cwd, f"{base_ref}..HEAD"),
            "behind_base": _count(cwd, f"HEAD..{base_ref}"),
            "last_commit": _git(cwd, "log", "-1", "--pretty=%s", check=False)[:100],
            "last_commit_at": int(commit_epoch) if commit_epoch.isdigit() else 0,
            "push_ready": dirty == 0 and branch not in ("", "(detached)") and unpushed > 0,
        }
    )


def parse_worktrees(
    repo: str, role: str, *, triangulations_only: bool = False
) -> list[dict[str, object]]:
    output = _git(repo, "worktree", "list", "--porcelain", check=False)
    result: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    for line in output.splitlines():
        if line.startswith("worktree "):
            if current:
                result.append(current)
            current = {
                "path": str(Path(line[9:]).resolve()),
                "role": role,
                "repo": repo,
                "branch": "?",
                "head": "",
            }
        elif current is not None and line.startswith("HEAD "):
            current["head"] = line[5:12]
        elif current is not None and line.startswith("branch "):
            current["branch"] = line[7:].removeprefix("refs/heads/")
        elif current is not None and line.strip() == "detached":
            current["branch"] = "(detached)"
    if current:
        result.append(current)

    # `git worktree list` intentionally keeps prunable entries until an
    # explicit prune. They are recovery metadata, not executable worktrees.
    # Omit them from the cockpit without deleting any Git metadata.
    result = [item for item in result if Path(str(item["path"])).is_dir()]
    for item in result:
        item["slug"] = _slug(str(item["path"]), str(item.get("branch") or ""))
    if triangulations_only:
        result = [item for item in result if item["slug"]]

    threads = [threading.Thread(target=_worktree_status, args=(item,)) for item in result]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return result


def discover_inventory(config_path: str | None = None) -> dict[str, object]:
    repos = load_repo_config(config_path)
    worktrees: list[dict[str, object]] = []
    for role, repo in repos.items():
        if Path(repo).is_dir():
            worktrees.extend(parse_worktrees(repo, role, triangulations_only=True))

    grouped: dict[str, list[dict[str, object]]] = {}
    for item in worktrees:
        slug = item.get("slug")
        if slug:
            grouped.setdefault(str(slug), []).append(item)
    archive_entries = load_archive_state().get("archived", {})
    archive_entries = archive_entries if isinstance(archive_entries, dict) else {}
    all_triangulations = [
        {
            "slug": slug,
            "worktrees": sorted(items, key=lambda item: ("back", "front", "app").index(str(item["role"]))),
            "dirty": sum(int(item["dirty"]) for item in items),
            "unpushed": sum(int(item["unpushed"]) for item in items),
            "last_activity": max((int(item["last_commit_at"]) for item in items), default=0),
            "complete_roles": sorted(str(item["role"]) for item in items),
            "archived": slug in archive_entries,
            "archive": archive_entries.get(slug),
        }
        for slug, items in grouped.items()
    ]
    all_triangulations.sort(key=lambda item: int(item["last_activity"]), reverse=True)
    triangulations = [item for item in all_triangulations if not item["archived"]]
    archived_triangulations = [item for item in all_triangulations if item["archived"]]
    return {
        "config": str(Path(config_path or CONFIG_PATH).expanduser()),
        "repos": repos,
        "worktrees": worktrees,
        "triangulations": triangulations,
        "archived_triangulations": archived_triangulations,
    }


def _common_dir(cwd: str) -> str:
    return _git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir", check=False)


def is_allowed_cwd(cwd: str) -> bool:
    path = Path(cwd).expanduser()
    if not path.is_dir():
        return False
    target = _common_dir(str(path))
    if not target:
        return False
    return any(
        target == _common_dir(repo)
        for repo in load_repo_config().values()
        if Path(repo).is_dir()
    )


def role_for_cwd(cwd: str) -> str | None:
    target = _common_dir(cwd)
    for role, repo in load_repo_config().items():
        if Path(repo).is_dir() and target == _common_dir(repo):
            return role
    return None


def command_for(key: str, cwd: str) -> list[str]:
    if key == "git-diff":
        base_ref = resolve_base_ref(cwd, role_for_cwd(cwd))
        quoted = shlex.quote(base_ref)
        return [
            "bash", "-c",
            f"git fetch origin --quiet 2>&1 && git diff {quoted}...HEAD --stat",
        ]
    if key not in STATIC_COMMANDS:
        raise ValueError(f"Comando desconocido: {key}")
    return list(STATIC_COMMANDS[key])


def validate_push(cwd: str) -> None:
    if not is_allowed_cwd(cwd):
        raise ValueError("worktree fuera de los tres repositorios autorizados")
    dirty = _git(cwd, "status", "--porcelain")
    if dirty:
        raise ValueError("el worktree tiene cambios sin commit")
    branch = _git(cwd, "branch", "--show-current", check=False)
    if not branch:
        raise ValueError("el worktree está detached; no se puede publicar de forma segura")


def verify_worktree(cwd: str, role: str) -> dict[str, object]:
    started = time.monotonic()
    result: dict[str, object] = {
        "role": role, "command": "", "returncode": None, "output": "",
        "executed": False, "state": "BLOCKED", "tested_revision": None,
    }
    try:
        subdir, command = VERIFY_COMMANDS[role]
        result["command"] = shlex.join(command)
        if os.environ.get("VERIFY_SKIP") == "1":
            result.update(state="SKIPPED", output="VERIFY_SKIP=1 — no promocionable")
            return result
        verify_cwd = Path(cwd) / subdir
        if not verify_cwd.is_dir():
            raise ValueError(f"no existe el directorio de verificación: {verify_cwd}")
        tool = "flutter" if role == "app" else "npm"
        if not shutil.which(tool) or not shutil.which(command[0]):
            raise ValueError(f"herramienta requerida no disponible: {tool}")
        if role == "app":
            if not (verify_cwd / "pubspec.yaml").is_file():
                raise ValueError("falta pubspec.yaml")
        else:
            package = json.loads((verify_cwd / "package.json").read_text())
            scripts = package.get("scripts", {}) if isinstance(package, dict) else {}
            required = ("typecheck", "format:check", "lint", "test:unit") if role == "back" else ("check:all",)
            if not isinstance(scripts, dict) or any(not isinstance(scripts.get(key), str) or not scripts[key].strip() for key in required):
                raise ValueError(f"scripts requeridos ausentes: {', '.join(required)}")
        before = _git(cwd, "rev-parse", "HEAD")
        branch = _git(cwd, "branch", "--show-current")
        if _git(cwd, "status", "--porcelain"):
            raise ValueError("verificación requiere estado limpio")
        result["tested_revision"] = before
        proc = subprocess.run(command, cwd=verify_cwd, text=True, capture_output=True,
                              timeout=900, check=False)
        result.update(executed=True, returncode=proc.returncode, output=(proc.stdout + proc.stderr)[-4000:],
                      state="PASS" if proc.returncode == 0 else "FAIL")
        if (_git(cwd, "rev-parse", "HEAD") != before
                or _git(cwd, "branch", "--show-current") != branch
                or _git(cwd, "status", "--porcelain")):
            result.update(state="BLOCKED", output="Repositorio cambió durante verificación; repetir")
    except subprocess.TimeoutExpired:
        result.update(executed=True, state="TIMEOUT", returncode=124, output="verificación superó 900s")
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        result.update(state="BLOCKED", output=str(error)[-4000:])
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - started, 6)
    return result


def project_info(cwd: str) -> dict[str, object]:
    role = role_for_cwd(cwd)
    info: dict[str, object] = {
        "cwd": cwd,
        "role": role,
        "branch": _git(cwd, "branch", "--show-current", check=False) or "(detached)",
        "base_ref": resolve_base_ref(cwd, role),
        "version": None,
    }
    pubspec = Path(cwd) / "pubspec.yaml"
    if pubspec.is_file():
        for line in pubspec.read_text(encoding="utf-8").splitlines():
            if line.startswith("version:"):
                info["version"] = line.split(":", 1)[1].strip()
                break
    return info


def runtime_env() -> dict[str, str]:
    env = os.environ.copy()
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + env.get("PATH", "")
    return env


def _run_git_command(cwd: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        text=True,
        capture_output=True,
        env=runtime_env(),
        check=False,
    )


def _revalidate_prepared(item: dict[str, object]) -> None:
    """Prove the worktree still matches the exact commit that passed the gate."""
    cwd = str(item["cwd"])
    validate_push(cwd)
    branch = _git(cwd, "branch", "--show-current", check=False)
    head = _git(cwd, "rev-parse", "HEAD", check=False)
    if branch != item["branch"] or head != item["head"]:
        raise ValueError(
            f"{item['role']} cambió después de la prevalidación; no se publicará un HEAD distinto"
        )


def promote_group_to_dev(slug: str, paths: list[str]) -> dict[str, object]:
    """Fast-forward one verified three-repository triangulation into dev.

    Every repository is refreshed and validated before the first remote dev
    update. Cross-repository pushes cannot be atomic, so any remote rejection
    returns a bounded partial receipt and never force-pushes.
    """
    if not slug or len(paths) != 3 or len(set(paths)) != 3:
        raise ValueError("la integración requiere exactamente tres worktrees únicos")

    prepared: list[dict[str, object]] = []
    roles: set[str] = set()
    for cwd in paths:
        if not is_allowed_cwd(cwd):
            raise ValueError("worktree fuera de los tres repositorios autorizados")
        fetch = _run_git_command(cwd, "fetch", "origin", "dev")
        if fetch.returncode:
            raise ValueError(f"no se pudo actualizar origin/dev en {cwd}: {fetch.stderr.strip()}")
        validate_push(cwd)
        role = role_for_cwd(cwd)
        branch = _git(cwd, "branch", "--show-current", check=False)
        if role is None or role in roles:
            raise ValueError("roles duplicados o desconocidos en la triangulación")
        if _slug(cwd, branch) != slug:
            raise ValueError(f"el worktree {cwd} no pertenece a la triangulación {slug}")
        if branch == "dev":
            raise ValueError("la integración debe partir de una rama de trabajo, no de dev")
        if _run_git_command(cwd, "merge-base", "--is-ancestor", "origin/dev", "HEAD").returncode:
            raise ValueError(f"{role} no contiene el último origin/dev; actualiza o rebasa antes de integrar")
        verification = verify_worktree(cwd, role)
        if (verification.get("state") != "PASS" or verification.get("executed") is not True
                or verification.get("returncode") != 0
                or verification.get("tested_revision") != _git(cwd, "rev-parse", "HEAD")):
            raise ValueError(
                f"verificación funcional falló en {role}: {verification['command']} "
                f"({verification.get('state', 'UNKNOWN')}, exit {verification.get('returncode')})\n{verification.get('output', '')}"
            )
        roles.add(role)
        prepared.append(
            {
                "cwd": cwd,
                "role": role,
                "branch": branch,
                "ahead": _count(cwd, "origin/dev..HEAD"),
                "head": verification["tested_revision"],
                "verification": verification,
            }
        )
    if roles != REQUIRED_ROLES:
        raise ValueError("la integración requiere backend, panel y app")

    # Recheck ALL verified snapshots before the first publication.
    for item in prepared:
        _revalidate_prepared(item)
    promoted: list[dict[str, object]] = []
    for item in sorted(prepared, key=lambda value: ("back", "front", "app").index(str(value["role"]))):
        cwd, branch, head = str(item["cwd"]), str(item["branch"]), str(item["head"])
        try:
            _revalidate_prepared(item)
        except ValueError as error:
            return {
                "ok": False,
                "error": str(error),
                "promoted": promoted,
                "failed": item,
            }
        if int(item["ahead"]) == 0:
            refresh = _run_git_command(cwd, "fetch", "origin", "dev")
            included = _run_git_command(cwd, "merge-base", "--is-ancestor", head, "origin/dev")
            if refresh.returncode or included.returncode:
                return {
                    "ok": False,
                    "error": f"no se pudo probar que {item['role']} ya está incluido en origin/dev",
                    "promoted": promoted,
                    "failed": {
                        **item,
                        "output": (refresh.stdout + refresh.stderr + included.stdout + included.stderr)[-4000:],
                    },
                }
            promoted.append(
                {
                    **item,
                    "status": "no-changes",
                    "dev_head": _git(cwd, "rev-parse", "origin/dev"),
                    "proof": "validated-head-is-ancestor-of-origin/dev",
                }
            )
            continue

        # Publish the immutable SHA that passed prevalidation, never a mutable
        # HEAD. A concurrent commit can therefore invalidate the receipt but
        # can never enter dev without passing a new gate.
        backup = _run_git_command(cwd, "push", "-u", "origin", f"{head}:refs/heads/{branch}")
        if backup.returncode:
            return {
                "ok": False,
                "error": f"no se pudo publicar la rama {branch}",
                "promoted": promoted,
                "failed": {**item, "output": (backup.stdout + backup.stderr)[-4000:]},
            }
        dev_push = _run_git_command(cwd, "push", "origin", f"{head}:refs/heads/dev")
        if dev_push.returncode:
            return {
                "ok": False,
                "error": f"origin/dev cambió o rechazó la integración de {item['role']}",
                "promoted": promoted,
                "failed": {**item, "output": (dev_push.stdout + dev_push.stderr)[-4000:]},
            }
        promoted.append(
            {
                **item,
                "status": "integrated",
                "dev_head": head,
                "proof": "validated-head-pushed-to-origin/dev",
                "output": (backup.stdout + backup.stderr + dev_push.stdout + dev_push.stderr)[-4000:],
            }
        )

    # Final receipt proof: every validated SHA remains the current clean
    # worktree HEAD and is reachable from the latest remote dev. This catches
    # changes racing after the per-repository revalidation.
    by_role = {str(item["role"]): item for item in promoted}
    for item in prepared:
        cwd, head, role = str(item["cwd"]), str(item["head"]), str(item["role"])
        refresh = _run_git_command(cwd, "fetch", "origin", "dev")
        try:
            _revalidate_prepared(item)
        except ValueError as error:
            return {
                "ok": False,
                "error": str(error),
                "promoted": promoted,
                "failed": item,
            }
        included = _run_git_command(cwd, "merge-base", "--is-ancestor", head, "origin/dev")
        if refresh.returncode or included.returncode:
            return {
                "ok": False,
                "error": f"el recibo final no pudo probar {role} en origin/dev",
                "promoted": promoted,
                "failed": {
                    **item,
                    "output": (refresh.stdout + refresh.stderr + included.stdout + included.stderr)[-4000:],
                },
            }
        by_role[role]["dev_head"] = _git(cwd, "rev-parse", "origin/dev")
        by_role[role]["proof"] = "validated-head-is-ancestor-of-origin/dev"
    return {"ok": True, "slug": slug, "promoted": promoted}


def promote_group_and_archive(slug: str, paths: list[str]) -> dict[str, object]:
    """Integrate one group and persist its closure in the same server operation."""
    # Fail before touching any remote when the durable registry cannot be read.
    load_archive_state()
    result = promote_group_to_dev(slug, paths)
    if not result.get("ok"):
        return result
    promoted = result.get("promoted")
    items = promoted if isinstance(promoted, list) else []
    evidence = "Integración validada (git+verify) a origin/dev · " + " · ".join(
        f"{item.get('role')}:{item.get('head')} in origin/dev@{item.get('dev_head')} "
        f"verify:{item.get('role')}:ok"
        for item in items
        if isinstance(item, dict)
    )
    try:
        receipt = set_triangulation_archived(slug, evidence, True,
            _verified={str(item["role"]): item["verification"] for item in items})
    except (OSError, ValueError) as error:
        return {
            **result,
            "ok": False,
            "integration_complete": True,
            "error": f"integrado a dev, pero no se pudo persistir el cierre: {error}",
        }
    return {**result, "archive": receipt}


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args: object) -> None:
        return

    def _origin_allowed(self) -> bool:
        origin = self.headers.get("Origin")
        return origin is None or origin in ALLOWED_ORIGINS

    def _cors(self) -> None:
        origin = self.headers.get("Origin")
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Vary", "Origin")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, x-token")

    def _deny_origin(self) -> None:
        self._json({"error": "origen no autorizado"}, 403)

    def do_OPTIONS(self) -> None:  # noqa: N802
        if not self._origin_allowed():
            self._deny_origin()
            return
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if not self._origin_allowed():
            self._deny_origin()
            return
        path = urlparse(self.path).path
        if path in ("/", "/index.html", "/cocoa-reference.html"):
            self._serve_html()
        elif path == "/api/health":
            self._json({"ok": True, "port": PORT, "config": CONFIG_PATH})
        elif path == "/api/triangulations":
            try:
                self._json(discover_inventory())
            except (OSError, ValueError) as error:
                self._json({"error": str(error)}, 500)
        elif path == "/api/parity":
            self._parity()
        else:
            self._json({"error": "ruta no encontrada"}, 404)

    def _parity(self) -> None:
        query = parse_qs(urlparse(self.path).query)
        project = query.get("project", [""])[0]
        if project not in ALLOWED_FIREBASE_PROJECTS:
            self._json({"error": "proyecto Firebase no autorizado"}, 400)
            return
        try:
            cwd = repo_path("back")
        except ValueError as error:
            self._json({"error": str(error)}, 500)
            return
        self._json(check_env_parity(cwd, project))

    def _body(self) -> dict[str, object]:
        length = int(self.headers.get("Content-Length", 0))
        if not length:
            return {}
        value = json.loads(self.rfile.read(length))
        return value if isinstance(value, dict) else {}

    def do_POST(self) -> None:  # noqa: N802
        if not self._origin_allowed():
            self._deny_origin()
            return
        try:
            body = self._body()
        except (ValueError, json.JSONDecodeError):
            self._json({"error": "JSON inválido"}, 400)
            return
        path = urlparse(self.path).path
        if path == "/api/worktrees":
            self._worktrees(body)
        elif path == "/api/info":
            self._info(body)
        elif path == "/api/run":
            self._run(body)
        elif path == "/api/push-all":
            self._push_all(body)
        elif path == "/api/promote-dev":
            self._promote_dev(body)
        elif path == "/api/archive-triangulation":
            self._archive_triangulation(body)
        elif path == "/api/proxy":
            self._proxy(body)
        else:
            self._json({"error": "ruta no encontrada"}, 404)

    def _serve_html(self) -> None:
        if not HTML.is_file():
            self._json({"error": f"{HTML.name} no encontrado"}, 404)
            return
        data = HTML.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self._cors()
        self.end_headers()
        self.wfile.write(data)

    def _json(self, value: object, status: int = 200) -> None:
        data = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self._cors()
        self.end_headers()
        self.wfile.write(data)

    def _validated_cwd(self, body: dict[str, object]) -> str:
        cwd = str(body.get("cwd") or "")
        if not is_allowed_cwd(cwd):
            raise ValueError("worktree fuera de los tres repositorios autorizados")
        return cwd

    def _worktrees(self, body: dict[str, object]) -> None:
        try:
            cwd = self._validated_cwd(body)
            role = role_for_cwd(cwd) or "unknown"
            self._json({"worktrees": parse_worktrees(cwd, role)})
        except ValueError as error:
            self._json({"error": str(error), "worktrees": []}, 400)

    def _info(self, body: dict[str, object]) -> None:
        try:
            cwd = self._validated_cwd(body)
            self._json(project_info(cwd))
        except ValueError as error:
            self._json({"error": str(error)}, 400)

    def _run(self, body: dict[str, object]) -> None:
        try:
            cwd = self._validated_cwd(body)
            key = str(body.get("cmd") or "")
            if key == "git-push":
                validate_push(cwd)
            command = command_for(key, cwd)
        except ValueError as error:
            self._json({"error": str(error)}, 409)
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Accel-Buffering", "no")
        self._cors()
        self.end_headers()
        try:
            process = subprocess.Popen(
                command,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=runtime_env(),
                text=True,
                bufsize=1,
            )
            assert process.stdout is not None
            for line in process.stdout:
                self.wfile.write(line.encode("utf-8"))
                self.wfile.flush()
            process.wait()
            self.wfile.write(f"\n[EXIT {process.returncode}]\n".encode("utf-8"))
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception as error:  # pragma: no cover - defensive streaming boundary
            self.wfile.write(f"[ERROR] {error}\n".encode("utf-8"))
            self.wfile.flush()

    def _push_all(self, body: dict[str, object]) -> None:
        raw_paths = body.get("paths")
        paths = [str(path) for path in raw_paths] if isinstance(raw_paths, list) else []
        if not paths:
            self._json({"error": "no se recibieron worktrees verificados"}, 400)
            return
        try:
            for cwd in paths:
                validate_push(cwd)
        except ValueError as error:
            self._json({"error": str(error), "pushed": []}, 409)
            return

        pushed: list[dict[str, object]] = []
        for cwd in paths:
            process = subprocess.run(
                command_for("git-push", cwd),
                cwd=cwd,
                text=True,
                capture_output=True,
                env=runtime_env(),
                check=False,
            )
            pushed.append(
                {
                    "cwd": cwd,
                    "exit": process.returncode,
                    "output": (process.stdout + process.stderr)[-4000:],
                }
            )
            if process.returncode:
                self._json({"error": "push parcial; revisa el recibo", "pushed": pushed}, 502)
                return
        self._json({"ok": True, "pushed": pushed})

    def _promote_dev(self, body: dict[str, object]) -> None:
        group = body.get("group") if isinstance(body.get("group"), dict) else {}
        slug = str(group.get("slug") or "")
        raw_paths = group.get("paths")
        paths = [str(path) for path in raw_paths] if isinstance(raw_paths, list) else []
        try:
            result = promote_group_and_archive(slug, paths)
        except (OSError, ValueError) as error:
            self._json({"error": str(error), "promoted": []}, 409)
            return
        self._json(result, 200 if result.get("ok") else 502)

    def _archive_triangulation(self, body: dict[str, object]) -> None:
        slug = str(body.get("slug") or "")
        action = str(body.get("action") or "archive")
        evidence = str(body.get("evidence") or "")
        inventory = discover_inventory()
        known = {
            str(item["slug"])
            for item in [
                *inventory.get("triangulations", []),
                *inventory.get("archived_triangulations", []),
            ]
            if isinstance(item, dict) and item.get("slug")
        }
        if slug not in known:
            self._json({"error": "triangulación desconocida"}, 404)
            return
        try:
            if action == "archive":
                receipt = set_triangulation_archived(slug, evidence, True)
            elif action == "restore":
                receipt = set_triangulation_archived(slug, evidence, False)
            else:
                raise ValueError("acción de archivo inválida")
        except (OSError, ValueError) as error:
            self._json({"error": str(error)}, 409)
            return
        self._json({"ok": True, "receipt": receipt})

    def _proxy(self, body: dict[str, object]) -> None:
        url = str(body.get("url") or "")
        method = str(body.get("method") or "POST").upper()
        headers = body.get("headers") if isinstance(body.get("headers"), dict) else {}
        payload = body.get("body")
        if not url.startswith(("http://", "https://")):
            self._json({"error": "URL inválida"}, 400)
            return
        try:
            data = json.dumps(payload).encode("utf-8") if payload is not None else None
            request = urllib.request.Request(url, data=data, method=method)
            request.add_header("Content-Type", "application/json")
            for key, value in headers.items():
                request.add_header(str(key), str(value))
            with urllib.request.urlopen(request, timeout=30) as response:
                response_body = response.read()
                self.send_response(response.status)
                self.send_header(
                    "Content-Type", response.headers.get("Content-Type", "application/json")
                )
                self._cors()
                self.end_headers()
                self.wfile.write(response_body)
        except urllib.error.HTTPError as error:
            self.send_response(error.code)
            self.send_header("Content-Type", "application/json")
            self._cors()
            self.end_headers()
            self.wfile.write(error.read())
        except Exception as error:
            self._json({"error": str(error)}, 502)


def _existing_server() -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/api/health", timeout=1) as response:
            return response.status == 200
    except Exception:
        return False


def main() -> None:
    if sys.argv[1:2] == ["--verify-closure"]:
        if len(sys.argv) != 3:
            raise SystemExit("usage: --verify-closure <slug>")
        report = verify_closure(sys.argv[2])
        print(json.dumps(report, ensure_ascii=False))
        raise SystemExit(0 if report["state"] == "PASS" else 2)
    open_browser = os.environ.get("COCOA_DEVTOOLS_NO_BROWSER") != "1"
    try:
        server = ThreadedHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError as error:
        if error.errno == errno.EADDRINUSE and _existing_server():
            if open_browser:
                webbrowser.open(f"http://localhost:{PORT}")
            print(f"Cocoa DevTools ya está activo en http://localhost:{PORT}")
            return
        raise

    url = f"http://localhost:{PORT}"
    print(f"\n  🥥 Cocoa DevTools → {url}")
    print(f"     Repositorios: {CONFIG_PATH}")
    print("     Ctrl+C para detener.\n")
    if open_browser:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDetenido.")
        server.shutdown()


if __name__ == "__main__":
    main()
