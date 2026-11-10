#!/usr/bin/env python3
"""Exercise saved delay settings and real greylisting retries on a test VM."""

import json
import os
from pathlib import Path
import shlex
import socket
import struct
import subprocess
import tempfile
import time
import uuid


def run(*args):
    """run(*args): Run a command and its arguments with a 30-second timeout.

    Return stdout and stderr together, or include them in the failure.
    """
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=30)
    if result.returncode:
        # Preserve the command's diagnostics when a guest operation fails.
        raise RuntimeError(result.stdout)
    return result.stdout.strip()


def helper(action, fixture="-", delay=""):
    """helper(action, [fixture], [delay]): Call the candidate through Webmin.

    fixture defaults to "-" for installed configuration. For apply, an empty
    delay tests the five-minute default. A supplied value overrides it.
    """
    return json.loads(run("perl", str(root / "t/fixtures/postgrey-delay-live.pl"),
                          str(module), str(root / "postgrey-lib.pl"), action,
                          str(fixture), str(delay)))


def wait_socket(path, process):
    """wait_socket(path, process): Wait for the process to create its socket."""
    for _ in range(100):
        if process.poll() is not None:
            # Stop waiting if startup failed before the listener was created.
            raise RuntimeError("greylisting daemon exited before listening")
        if path.exists():
            # The listener is available for the first protocol request.
            return
        time.sleep(0.05)
    raise RuntimeError("greylisting daemon did not create its socket")


def postgrey_request(path, sender):
    """postgrey_request(path, sender): Query RCPT policy over a Unix socket."""
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(5)
        client.connect(str(path))
        # Use the same client and recipient for each retry from this sender.
        request = ("request=smtpd_access_policy\nprotocol_state=RCPT\n"
                   "client_address=192.0.2.97\nclient_name=client.example.invalid\n"
                   f"sender={sender}\nrecipient=receiver@example.invalid\n\n")
        client.sendall(request.encode())
        return client.recv(4096).decode()


def read_exact(client, length):
    """read_exact(client, length): Read length bytes from a connected socket."""
    data = b""
    while len(data) < length:
        part = client.recv(length - len(data))
        if not part:
            # A closed connection cannot supply the rest of the reply.
            raise RuntimeError("milter closed the connection")
        data += part
    return data


def milter_request(path, sender):
    """milter_request(path, sender): Query a recipient via a milter socket."""
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(5)
        client.connect(str(path))

        def exchange(command, payload):
            """exchange(command, payload): Send a frame and read its reply."""
            packet = command + payload
            client.sendall(struct.pack("!I", len(packet)) + packet)
            length = struct.unpack("!I", read_exact(client, 4))[0]
            return read_exact(client, length)

        # Offer no protocol optimizations so every callback gets a response.
        assert exchange(b"O", struct.pack("!III", 6, 0xFF, 0)).startswith(b"O")
        connect = (b"client.example.invalid\0" + b"4" + struct.pack("!H", 2525)
                   + b"192.0.2.97\0")
        assert exchange(b"C", connect) == b"c"
        assert exchange(b"H", b"client.example.invalid\0") == b"c"
        assert exchange(b"M", f"<{sender}>\0".encode()) == b"c"
        reply = exchange(b"R", b"<receiver@example.invalid>\0")
        client.sendall(struct.pack("!I", 1) + b"Q")
        return reply


def test_postgrey(directory):
    """test_postgrey(directory): Save package options and test a short delay."""
    # Keep the delay inside POSTGREY_OPTS, before the trailing comment.
    fixture = directory / "postgrey-defaults"
    fixture.write_text('POSTGREY_OPTS="--inet=10023" # "Custom options"\n')
    helper("apply", fixture)
    assert fixture.read_text() == ('POSTGREY_OPTS="--inet=10023 --delay=300" '
                                   '# "Custom options"\n')
    # Save package options and running state before testing the real service.
    info = helper("get")
    options = Path(info["options"])
    original = options.read_bytes()
    active = subprocess.run(["systemctl", "is-active", "--quiet", "postgrey"]).returncode == 0
    try:
        # Check the default and manual override with the actual package service.
        helper("apply")
        run("systemctl", "restart", "postgrey")
        assert "--delay=300" in helper("get")["args"]
        helper("apply", delay=2)
        run("systemctl", "restart", "postgrey")
        info = helper("get")
        assert "--delay=2" in info["args"], info

        # Test retries with the saved delay and a private database and listener.
        path = directory / "postgrey.sock"
        database = directory / "db"
        database.mkdir()
        command = ["postgrey", f"--unix={path}", f"--dbdir={database}",
                   "--user=root", "--group=root", "--auto-whitelist-clients=0"]
        # Copy only the active delay into the isolated daemon's arguments.
        command += [arg for arg in shlex.split(info["args"])
                    if arg.startswith("--delay=")]
        # rejected(reply), accepted(reply): Check Postgrey's policy responses.
        exercise(command, path, directory, postgrey_request,
                 lambda reply: "action=DEFER_IF_PERMIT" in reply,
                 lambda reply: "action=PREPEND" in reply or "action=DUNNO" in reply)
    finally:
        # Restore the package configuration and the service's original state.
        options.write_bytes(original)
        run("systemctl", "restart" if active else "stop", "postgrey")
    print("PASS: Postgrey five-minute default, manual override and live retries")


def test_milter(directory):
    """test_milter(directory): Check defaults and retries with a private ACL."""
    path = directory / "milter.sock"
    fixture = directory / "greylist.conf"
    # Reject unclosed quotes without saving changes to earlier lines.
    for prefix, line in (("racl whitelist default ", 1),
                         ("racl whitelist default delay 30m \\\n", 2)):
        fixture.write_text(prefix + 'msg "Try again\n')
        original = fixture.read_bytes()
        try:
            helper("apply", fixture)
        except RuntimeError as error:
            # The failure must identify the malformed fixture and its line.
            assert f"Cannot read the greylisting rule on line {line}" in str(error)
            assert str(fixture) in str(error)
        else:
            # Accepting the broken rule would let an invalid update proceed.
            raise AssertionError("unclosed quote was accepted")
        # Failed updates must preserve file bytes and release the config lock.
        assert fixture.read_bytes() == original
        assert not Path(str(fixture) + ".lock").exists()

    # Use a private daemon with a client-specific rule and a default ACL.
    fixture.write_text(f'socket "{path}"\nuser "root"\n'
                       f'dumpfile "{directory / "db"}"\nnospf\nnoauth\n'
                       'racl greylist addr 192.0.2.1 delay 1h\n'
                       'racl whitelist default msg "Try again # later"\n')
    # Check the fixture and the saved five-minute default with the real parser.
    run("milter-greylist", "-c", "-f", str(fixture))
    helper("apply", fixture)
    assert 'racl greylist default msg "Try again # later" delay 300s' in fixture.read_text()
    run("milter-greylist", "-c", "-f", str(fixture))
    # Shorten the retry test while keeping the client-specific delay intact.
    helper("apply", fixture, 2)
    assert 'racl greylist default msg "Try again # later" delay 2s' in fixture.read_text()
    assert "addr 192.0.2.1 delay 1h" in fixture.read_text()
    run("milter-greylist", "-c", "-f", str(fixture))
    # rejected(reply), accepted(reply): Check milter's response codes.
    exercise(["milter-greylist", "-D", "-f", str(fixture)], path, directory,
             milter_request, lambda reply: reply.startswith(b"y451"),
             lambda reply: reply == b"c")
    print("PASS: milter parse errors leave config intact; defaults, overrides and live retries")


def exercise(command, path, directory, request, rejected, accepted):
    """exercise(command, path, directory, request, rejected, accepted):
    Test retries against a daemon configured with a two-second delay.

    command is its argument list, path its socket and directory its log folder.
    request(path, sender) returns a reply. rejected(reply) and accepted(reply)
    check the expected outcomes before and after the delay.
    """
    # A unique sender prevents earlier requests from affecting this test.
    sender = f"delay-{uuid.uuid4().hex}@example.invalid"
    with (directory / "daemon.log").open("w+") as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
        try:
            # The initial request and an immediate retry must both be rejected.
            wait_socket(path, process)
            first = request(path, sender)
            assert rejected(first), repr(first)
            early = request(path, sender)
            assert rejected(early), repr(early)
            # Retry after the configured two-second delay has elapsed.
            time.sleep(3)
            later = request(path, sender)
            assert accepted(later), repr(later)
        except Exception:
            # Include daemon output when a protocol exchange or assertion fails.
            log.seek(0)
            print(log.read())
            raise
        finally:
            # Stop the test daemon before its temporary files are removed.
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                # Force cleanup if the daemon does not stop within ten seconds.
                process.kill()
                process.wait()


if __name__ == "__main__":
    # Run the integration checks only when invoked as the test driver.
    if not (os.uname().sysname == "Linux" and os.geteuid() == 0
            and os.environ.get("VIRTUALMIN_GREYLIST_VM_TEST") == "1"):
        # Require Linux, root and the explicit VM test opt-in.
        raise SystemExit("Run only on an opted-in Linux debug VM")
    # Locate the candidate checkout and the installed Webmin module.
    root = Path(__file__).resolve().parent.parent
    module = next(path for path in (Path("/usr/libexec/webmin/virtual-server"),
                                   Path("/usr/share/webmin/virtual-server"))
                  if path.is_dir())
    # Remove protocol fixtures when the test finishes or raises an exception.
    with tempfile.TemporaryDirectory(prefix="greylist-delay-") as tmp:
        directory = Path(tmp)
        if helper("get")["backend"] == "milter":
            # Exercise milter's ACL format and wire protocol.
            test_milter(directory)
        else:
            # Exercise Postgrey's package options and policy protocol.
            test_postgrey(directory)
