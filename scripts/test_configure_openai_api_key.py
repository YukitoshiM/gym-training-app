#!/usr/bin/env python3

from __future__ import annotations

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY / "scripts" / "configure_openai_api_key.sh"


class ConfigureOpenAIAPIKeyTests(unittest.TestCase):
    def test_rejects_unknown_environment_before_prompting(self) -> None:
        result = subprocess.run(
            [str(SCRIPT), "preview"],
            cwd=REPOSITORY,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 64)
        self.assertIn("staging|production", result.stderr)

    def test_stores_key_and_registers_cloudflare_secret_without_printing_it(self) -> None:
        fake_key = "sk-svcacct-" + ("x" * 180)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            security_log = root / "security.log"
            npx_log = root / "npx.log"
            fake_security = root / "security"
            fake_npx = root / "npx"
            fake_swift = root / "swift"
            fake_security.write_text(
                "#!/bin/sh\n"
                'printf "%s\\n" "$*" >> "$FAKE_SECURITY_LOG"\n'
                'if [ "$1" = "find-generic-password" ]; then printf "%s" "$FAKE_OPENAI_KEY"; fi\n',
                encoding="utf-8",
            )
            fake_npx.write_text(
                "#!/bin/sh\n"
                'printf "%s\\n" "$*" >> "$FAKE_NPX_LOG"\n'
                'if [ "$2" = "whoami" ]; then echo "You are logged in"; exit 0; fi\n'
                'if [ "$2" = "secret" ] && [ "$3" = "put" ]; then\n'
                '  value=$(cat); printf "secret_length=%s\\n" "${#value}" >> "$FAKE_NPX_LOG"; exit 0\n'
                "fi\n"
                'if [ "$2" = "secret" ] && [ "$3" = "list" ]; then\n'
                '  echo \'[{"name":"OPENAI_API_KEY"}]\'; exit 0\n'
                "fi\n"
                "exit 1\n",
                encoding="utf-8",
            )
            fake_swift.write_text(
                "#!/bin/sh\n"
                'value=$(cat); printf "keychain_length=%s\\n" "${#value}" >> "$FAKE_SECURITY_LOG"\n',
                encoding="utf-8",
            )
            fake_security.chmod(fake_security.stat().st_mode | stat.S_IXUSR)
            fake_npx.chmod(fake_npx.stat().st_mode | stat.S_IXUSR)
            fake_swift.chmod(fake_swift.stat().st_mode | stat.S_IXUSR)

            environment = os.environ.copy()
            environment.update(
                {
                    "BODYMODE_SECURITY_BIN": str(fake_security),
                    "BODYMODE_NPX_BIN": str(fake_npx),
                    "BODYMODE_SWIFT_BIN": str(fake_swift),
                    "FAKE_SECURITY_LOG": str(security_log),
                    "FAKE_NPX_LOG": str(npx_log),
                    "FAKE_OPENAI_KEY": fake_key,
                }
            )
            result = subprocess.run(
                [str(SCRIPT), "production"],
                cwd=REPOSITORY,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
                input=f"{fake_key}\n",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(fake_key, result.stdout)
            self.assertNotIn(fake_key, result.stderr)
            self.assertIn(f"keychain_length={len(fake_key)}", security_log.read_text())
            npx_calls = npx_log.read_text()
            self.assertIn("secret put OPENAI_API_KEY --env production", npx_calls)
            self.assertIn(f"secret_length={len(fake_key)}", npx_calls)


if __name__ == "__main__":
    unittest.main()
