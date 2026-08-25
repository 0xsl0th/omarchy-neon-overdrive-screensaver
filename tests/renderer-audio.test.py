#!/usr/bin/env python3
"""PTY integration test for the Cava/TTFX renderer handoff and cleanup."""

from __future__ import annotations

import errno
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import tempfile
import time


PROJECT_ROOT = Path(__file__).resolve().parent.parent
RENDERER = PROJECT_ROOT / "bin" / "neon-overdrive-render"
ACTIVE_FRAME = "60;60;60;60;60;60;35;35;35;35;35;35;20;20;20;20;20;20;"


def write_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)


def process_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def wait_gone(pid: int, timeout: float = 2.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not process_exists(pid):
            return True
        time.sleep(0.02)
    return not process_exists(pid)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="neon-overdrive-renderer-test.") as tmp:
        root = Path(tmp)
        fake_bin = root / "bin"
        runtime = root / "runtime"
        fake_bin.mkdir()
        runtime.mkdir()
        cava_pid_file = root / "cava.pid"
        ttfx_pid_file = root / "ttfx.pid"

        write_executable(
            fake_bin / "hyprctl",
            """#!/usr/bin/env bash
if [[ ${1:-} == activewindow ]]; then
  printf '%s\\n' '{"class":"org.omarchy.screensaver"}'
fi
exit 0
""",
        )
        write_executable(
            fake_bin / "pkill",
            """#!/usr/bin/env bash
exit 0
""",
        )
        write_executable(
            fake_bin / "ttfx",
            """#!/usr/bin/env bash
printf '%s\\n' "$BASHPID" >"$NEON_TEST_TTFX_PID"
printf '%s\\n' 'TTFX-STATIC'
trap 'exit 0' TERM INT HUP QUIT
while true; do sleep 0.1; done
""",
        )
        write_executable(
            fake_bin / "cava",
            f"""#!/usr/bin/env bash
printf '%s\\n' "$BASHPID" >"$NEON_TEST_CAVA_PID"
trap 'exit 0' TERM INT HUP QUIT
for ((frame_index = 0; frame_index < 12; frame_index++)); do
  printf '%s\\n' '{ACTIVE_FRAME}'
  sleep 0.04
done
while true; do
  printf '%s\\n' '0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;'
  sleep 0.04
done
""",
        )

        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{fake_bin}:{env['PATH']}",
                "XDG_RUNTIME_DIR": str(runtime),
                "NEON_TEST_CAVA_PID": str(cava_pid_file),
                "NEON_TEST_TTFX_PID": str(ttfx_pid_file),
                "NEON_OVERDRIVE_AUDIO": "auto",
                "TERM": "xterm-256color",
            }
        )

        master_fd, slave_fd = pty.openpty()
        process = subprocess.Popen(
            [str(RENDERER)],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            env=env,
            start_new_session=True,
            close_fds=True,
        )
        os.close(slave_fd)
        output = bytearray()

        try:
            deadline = time.monotonic() + 8.0
            while time.monotonic() < deadline:
                if b"AUDIO LINK: LIVE" in output and output.count(b"TTFX-STATIC") >= 2:
                    break
                ready, _, _ = select.select([master_fd], [], [], 0.1)
                if not ready:
                    if process.poll() is not None:
                        break
                    continue
                try:
                    output.extend(os.read(master_fd, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break

            assert b"AUDIO LINK: LIVE" in output, (
                "renderer never entered music-reactive mode; output tail: "
                + repr(bytes(output[-500:]))
            )
            assert output.count(b"TTFX-STATIC") >= 2, (
                "renderer did not return to TTFX after silence; output tail: "
                + repr(bytes(output[-500:]))
            )
            assert cava_pid_file.exists(), "fake Cava did not start"
            assert ttfx_pid_file.exists(), "fake TTFX did not start"

            cava_pid = int(cava_pid_file.read_text(encoding="utf-8").strip())
            ttfx_pid = int(ttfx_pid_file.read_text(encoding="utf-8").strip())
            process.send_signal(signal.SIGTERM)
            shutdown_deadline = time.monotonic() + 5
            while process.poll() is None and time.monotonic() < shutdown_deadline:
                ready, _, _ = select.select([master_fd], [], [], 0.05)
                if ready:
                    try:
                        output.extend(os.read(master_fd, 65536))
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
            return_code = process.poll()
            if return_code is None:
                diagnostics = subprocess.run(
                    [
                        "ps",
                        "-o",
                        "pid=,ppid=,stat=,wchan=,args=",
                        "-p",
                        f"{process.pid},{cava_pid},{ttfx_pid}",
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                ).stdout
                raise AssertionError(
                    "renderer did not exit after SIGTERM:\n"
                    + diagnostics
                    + "\n[output tail]\n"
                    + repr(bytes(output[-2000:]))
                )
            assert return_code == 0, f"renderer exited with {return_code}"
            assert wait_gone(cava_pid), f"owned Cava process {cava_pid} leaked"
            assert wait_gone(ttfx_pid), f"owned TTFX process {ttfx_pid} leaked"
        finally:
            os.close(master_fd)
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)

    print("Renderer audio integration test passed.")


if __name__ == "__main__":
    main()
