"""Opt-in live test for a disposable Debian/Ubuntu Virtualmin VM.

Run with VIRTUALMIN_PROFTPD_LIVE_VM_TEST=1. Temporarily changes ProFTPD log
paths and restarts the service; restores configuration and removes task data.
"""

import ftplib
import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import subprocess
import tempfile
import time

if os.environ.get("VIRTUALMIN_PROFTPD_LIVE_VM_TEST") != "1":
    raise SystemExit("Set VIRTUALMIN_PROFTPD_LIVE_VM_TEST=1 on a disposable VM")

source = Path(__file__).resolve().parent.parent / "proftpd-lib.pl"
main = Path("/etc/proftpd/proftpd.conf")
included = Path("/etc/proftpd/conf.d/virtualmin.conf")
rule = Path("/etc/logrotate.d/proftpd-core")
original = {path: path.read_bytes() for path in (main, included, rule)}
checks = 0


def check(condition, description):
    global checks
    if not condition:
        raise AssertionError(description)
    checks += 1
    print(f"PASS {checks}: {description}", flush=True)


def run(*args):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=30)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}): {result.stdout}")
    return result.stdout


def set_log(text, directive, path):
    updated, count = re.subn(rf"(?m)^([ \t]*{directive}[ \t]+).*$",
                            lambda match: f'{match[1]}"{path}"', text)
    if count != 1:
        raise AssertionError(f"Expected one {directive} directive, found {count}")
    return updated


def connections():
    # Opening sessions is enough to exercise both service log destinations.
    with socket.create_connection(("127.0.0.1", 2222), timeout=10) as client:
        check(client.recv(4096).startswith(b"SSH-2.0-mod_sftp"), "real SFTP server answers")
        client.sendall(b"SSH-2.0-logrotate-path-test\r\n")
        time.sleep(0.3)
    with ftplib.FTP_TLS(context=ssl._create_unverified_context(), timeout=10) as client:
        client.connect("127.0.0.1", 21)
        client.auth()
        check(isinstance(client.sock, ssl.SSLSocket), "real FTP TLS handshake succeeds")
        client.quit()
    time.sleep(1)


# Load the candidate helper into the installed Webmin runtime, without
# replacing any installed module code or exposing configuration contents.
apply_code = r'''
use strict;
use warnings;
no warnings qw(once redefine);
$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
open(my $mc, '<', '/etc/webmin/miniserv.conf') or die $!;
my ($root) = map { /^root=(.*)/ ? $1 : () } <$mc>;
close($mc);
chdir("$root/virtual-server") or die $!;
$0 = "$root/virtual-server/proftpd-live-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');
{
    package virtual_server;
    do $ARGV[0] or die $@ || $!;
}
print virtual_server::setup_proftpd_logrotate(), "\n";
'''

check(run("systemctl", "is-active", "proftpd").strip() == "active", "ProFTPD starts active")
logdir = Path(tempfile.mkdtemp(prefix="codex-proftpd-paths-", dir="/var/log"))
try:
    with tempfile.TemporaryDirectory(prefix="proftpd-paths-live-") as work:
        system = logdir / "daemon.log"
        sftp = logdir / "secure shell.log"
        tls = logdir / "encrypted.log"
        main.write_text(set_log(original[main].decode(), "SystemLog", system))
        included.write_text(set_log(set_log(original[included].decode(), "TLSLog", tls), "SFTPLog", sftp))
        stock_rule = original[rule].decode()
        if stock_rule.count("/var/log/proftpd/proftpd.log") != 1:
            raise AssertionError("Expected the stock ProFTPD SystemLog rotation entry")
        custom_rule = stock_rule.replace("/var/log/proftpd/proftpd.log", str(system))
        rule.write_text(custom_rule)
        run("proftpd", "-t")
        run("systemctl", "restart", "proftpd")
        check(run("perl", "-e", apply_code, str(source)).strip() == "2", "repair reads both custom paths from the live ProFTPD configuration")
        check(rule.read_text().split("{", 1)[1] == custom_rule.split("{", 1)[1], "repair preserves all package options and restart scripts")
        check(run("perl", "-e", apply_code, str(source)).strip() == "0", "second repair makes no changes")
        run("logrotate", "--debug", "--state", "/dev/null", "/etc/logrotate.conf")
        check(True, "complete native logrotate configuration is valid")
        connections()
        check(all(path.exists() and path.stat().st_size for path in (system, sftp, tls)), "real service traffic populates all three custom logs")
        before = {path: path.stat() for path in (sftp, tls)}
        old_pid = run("systemctl", "show", "proftpd", "--property=MainPID", "--value")
        run("logrotate", "--force", "--state", str(Path(work) / "state"), str(rule))
        check(run("systemctl", "is-active", "proftpd").strip() == "active", "ProFTPD remains active after rotation")
        new_pid = run("systemctl", "show", "proftpd", "--property=MainPID", "--value")
        check(int(new_pid) > 0 and new_pid != old_pid, "actual package postrotate command restarts ProFTPD")
        for path in (sftp, tls):
            check(Path(str(path) + ".1").stat().st_ino == before[path].st_ino, f"{path.name} rotates into its archive")
            check(path.stat().st_ino != before[path].st_ino, f"{path.name} gets a new active inode")
            check(path.stat().st_mode & 0o7777 == 0o640, f"{path.name} has package permissions")
        sizes = {path: path.stat().st_size for path in (sftp, tls)}
        archives = {path: Path(str(path) + ".1").read_bytes() for path in (sftp, tls)}
        connections()
        for path in (sftp, tls):
            check(path.stat().st_size > sizes[path], f"new connections write to the new {path.name}")
            check(Path(str(path) + ".1").read_bytes() == archives[path], f"archived {path.name} stays unchanged")
finally:
    # Restore the service before removing its temporary log destinations.
    for path, contents in original.items():
        path.write_bytes(contents)
    run("proftpd", "-t")
    run("systemctl", "restart", "proftpd")
    check(all(path.read_bytes() == contents for path, contents in original.items()), "original configuration restored exactly")
    check(run("systemctl", "is-active", "proftpd").strip() == "active", "ProFTPD is active with its original configuration")
    shutil.rmtree(logdir)

print(f"PASS: all {checks} live checks passed", flush=True)
