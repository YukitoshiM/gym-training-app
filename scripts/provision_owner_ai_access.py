#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import secrets
from pathlib import Path


SERVER_DIR = Path(__file__).resolve().parents[1] / "local_llm_server"
SUPPORT_DIR = Path.home() / "Library/Application Support/BodyMode/local_ai_server"
PUBLIC_KEY_FILE = SERVER_DIR / ".api_key"
OWNER_KEY_FILE = SUPPORT_DIR / "owner_enrollment_key"
HEALTH_KEY_FILE = SUPPORT_DIR / ".health_enrollment_key"
ENROLLMENT_FILE = SUPPORT_DIR / "enrollment_keys.json"


def digest(value: str) -> str:
    return "sha256:" + hashlib.sha256(value.encode("utf-8")).hexdigest()


def load_or_create_credential(path: Path) -> str:
    if path.exists():
        credential = path.read_text(encoding="utf-8").strip()
        if credential:
            return credential

    credential = secrets.token_urlsafe(48)
    path.write_text(credential + "\n", encoding="utf-8")
    path.chmod(0o600)
    return credential


def load_existing_enrollments() -> dict[str, str]:
    if not ENROLLMENT_FILE.exists():
        return {}
    try:
        value = json.loads(ENROLLMENT_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return {}
    return {str(key): str(item) for key, item in value.items()} if isinstance(value, dict) else {}


def main() -> int:
    public_key = PUBLIC_KEY_FILE.read_text(encoding="utf-8").strip()
    if not public_key:
        raise RuntimeError("The existing public enrollment key is empty")

    SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    owner_key = load_or_create_credential(OWNER_KEY_FILE)
    health_key = load_or_create_credential(HEALTH_KEY_FILE)

    enrollments = load_existing_enrollments()
    enrollments.update(
        {
            "public": digest(public_key),
            "owner": digest(owner_key),
            "health-monitor": digest(health_key),
        }
    )
    ENROLLMENT_FILE.write_text(
        json.dumps(enrollments, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    ENROLLMENT_FILE.chmod(0o600)
    print(f"Enrollment subjects provisioned at {ENROLLMENT_FILE}")
    print(f"Owner credential stored locally at {OWNER_KEY_FILE}")
    print(f"Health monitor credential stored locally at {HEALTH_KEY_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
