# Een ntfy-bericht als een playbook faalt of een host niet bereikt. Alleen
# waar HOMELAB_NTFY_URL en HOMELAB_NTFY_TOKEN_FILE gezet zijn: in Semaphore
# (roles/semaphore), niet op de laptop. Semaphore zelf kent geen ntfy.
# HOMELAB_NTFY_CLICK, als hij gezet is, is waar een tik op de melding heen gaat.
from __future__ import annotations

DOCUMENTATION = """
name: ntfy_on_failure
type: notification
short_description: ntfy-bericht als een playbook faalt
description:
  - Stuurt na de PLAY RECAP een bericht als een host faalde of onbereikbaar was.
  - Doet niets in check mode, en niets zonder HOMELAB_NTFY_URL en HOMELAB_NTFY_TOKEN_FILE.
"""

import os
import urllib.request

from ansible import context
from ansible.plugins.callback import CallbackBase

MAX_LINES = 15


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "notification"
    CALLBACK_NAME = "ntfy_on_failure"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()
        self._playbook = "?"
        self._problems = []

    def v2_playbook_on_start(self, playbook):
        self._playbook = os.path.basename(playbook._file_name)

    def v2_runner_on_failed(self, result, ignore_errors=False):
        if not ignore_errors:
            self._problems.append((result._host.get_name(), result._task.get_name()))

    def v2_runner_on_unreachable(self, result):
        self._problems.append((result._host.get_name(), "onbereikbaar"))

    def v2_playbook_on_stats(self, stats):
        url = os.environ.get("HOMELAB_NTFY_URL")
        token_file = os.environ.get("HOMELAB_NTFY_TOKEN_FILE")
        # Check mode: drift.yml draait site.yml --check als subproces, en die
        # mag falen zonder dat het een melding is.
        if not url or not token_file or context.CLIARGS.get("check"):
            return

        bad = {h for h in stats.processed if stats.failures.get(h) or stats.dark.get(h)}
        if not bad:
            return

        # Een fout die een rescue opving, staat in _problems maar niet in bad.
        lines = list(dict.fromkeys(f"{h}: {t}" for h, t in self._problems if h in bad))
        if len(lines) > MAX_LINES:
            lines = lines[:MAX_LINES] + [f"... en nog {len(lines) - MAX_LINES}"]
        body = "\n".join(lines) or ", ".join(sorted(bad))

        try:
            with open(token_file, encoding="utf-8") as f:
                token = f.read().strip()
            headers = {
                "Authorization": f"Bearer {token}",
                "Title": f"Semaphore: {self._playbook} faalde",
                "Priority": "high",
                "Tags": "warning",
            }
            click = os.environ.get("HOMELAB_NTFY_CLICK")
            if click:
                headers["Click"] = click
            request = urllib.request.Request(url, data=body.encode("utf-8"), headers=headers)
            urllib.request.urlopen(request, timeout=10).close()
        # OSError dekt het tokenbestand en elke netwerkfout (URLError, timeout);
        # ValueError een URL die niet klopt. Een melding die niet weg kan, mag
        # de job niet breken.
        except (OSError, ValueError) as e:
            self._display.warning(f"ntfy_on_failure: geen melding verstuurd: {e}")
