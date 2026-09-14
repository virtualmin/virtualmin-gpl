# Virtualmin test suite

This `t/` tree holds tests for virtualmin-gpl. Companion infrastructure lives
in the Webmin repo (`webmin/t/`); the patterns here should stay compatible
with that suite where practical.

`functional-test.pl` already provides significant integration coverage, but it
is not yet a lightweight `prove` target. Most tests in this directory are
smaller checks for normal development and CI. Tests that change services or
create domains require an explicit opt-in on a disposable VM.

## Running tests

```sh
prove -lr t
prove t/compile.t
VIRTUALMIN_COMPILE_T_FILTER='^\./backup' prove t/compile.t
```

`prove` and `Test::More` are core Perl modules. On RPM-based distros, install
`perl-Test-Harness` if `prove` is not already available.

On a disposable Virtualmin host, run `functional-test.pl --test apacheclone`
using the script's full path for Apache cloning integration coverage. This group
uses CLI commands to create, clone and validate websites, including PHP-FPM
configuration when available. HTTP/HTTPS requests check that the clone serves
its copied page after the source is deleted. The group uses `.invalid` domain
names with direct IP requests, cleans up both domains, and skips non-Apache
website plugins. Internal lock cleanup and nested SSL cache behavior are covered
by `apache-clone-locks.t`.

To run the additional Apache cloning checks on a disposable Linux VM as root:

```sh
VIRTUALMIN_APACHE_CLONE_VM_TEST=1 prove -v t/apache-clone-vm.t
```

This tests the VM's installed Virtualmin module, so install the candidate code
there first. It requires Apache, SSL, `curl`, and `timeout`. It creates three
`.invalid` domains and Unix accounts, checks document roots, executes PHP over
HTTP/HTTPS when PHP-FPM is available, and checks lock release with missing
virtual hosts. It also forces certificate sharing to break and checks that
`SSLProtocol` survives in the saved Apache file. A clone with a missing source
SSL virtual host must exit with a failure status. PHP checks are explicitly
skipped without FPM. Cleanup restores the SSL fixture's Apache files before
deleting all three domains. The test skips by default and on non-Linux systems.

To test clone completion on a disposable Apache VM, run
`VIRTUALMIN_CLONE_POST_VM_TEST=1 prove -v t/clone-post-actions-vm.t` as root.
It checks after-clone commands, rejected Apache configuration, a failed reload
command, and a post-action exception. It creates seven domains, restores the
temporary invalid vhost, and removes the domains and accounts afterward.
Install the candidate code in the VM's Virtualmin module first; the test requires
`curl` and `timeout`.

To test Webmin preference cloning on a disposable Virtualmin VM, run
`VIRTUALMIN_WEBMIN_CLONE_VM_TEST=1 prove -v t/webmin-clone-vm.t` as root.
Install the candidate code in the VM's Virtualmin module first. It checks that
clones inherit explicit and default language/theme preferences without changing
the source user. It requires local Webmin users, Authentic Theme and `timeout`,
and removes its three domains, Unix accounts and Webmin accounts afterward.

On a disposable Virtualmin host with local PostgreSQL, run
`VIRTUALMIN_POSTGRES_CLONE_VM_TEST=1 prove -v t/postgres-clone-vm.t` as root.
Install the candidate code in the VM's Virtualmin module first. The test checks
cloning with no databases, copied table data, and failure when one database name
clashes. It requires `psql`, `runuser`, and `timeout`, and removes its four domains,
Unix accounts, PostgreSQL roles, and databases afterward.

On a disposable Virtualmin host with local MySQL or MariaDB, run
`VIRTUALMIN_MYSQL_CLONE_VM_TEST=1 prove -v t/mysql-clone-vm.t` as root.
Install the candidate code in the VM's Virtualmin module first. The test checks
empty and populated clones, allowed hosts, a database name clash, an invalid view
that prevents dumping, and a corrupted dump rejected by the real importer.
It requires `timeout` and removes its six domains, Unix accounts, database users,
and databases afterward.

On a disposable Virtualmin Pro host, run
`VIRTUALMIN_DNS_VM_TEST=1 prove -v t/dns-cloud-migration-vm.t` to test DNS
migration with real BIND zones and a simulated cloud provider. It creates and
removes a DNS-only `.invalid` domain and does not contact Cloudflare.

## Current tests

On a disposable Virtualmin VM, install the candidate code and run
`VIRTUALMIN_DOMAIN_CONFIG_VM_TEST=1 prove -v t/domain-config-vm.t` as root.
It creates a temporary `.invalid` domain and checks concurrent config writes,
login collection across disable/enable operations, nested locks, scheduled
disabling, owner limits, feature toggles, and certificate generation and installation.
The test uses a private login-data fixture and does not contact an ACME service.
It removes its domain and account afterward and requires `timeout`.

| File | What it checks |
| --- | --- |
| `compile.t` | Every discovered `.pl` and `.cgi` parses cleanly with `perl -c`. It catches syntax and compile-time module-loading breakage without running normal script bodies. |
| `dns-cloud-migration-vm.t` | Explicit DNS migration destinations override templates and alias targets, preserve records, and restore the original provider after a setup failure. Requires a disposable Virtualmin Pro host. |
| `apache-clone-locks.t` | Apache cloning keeps parsed directives under a web lock, preserves them across nested SSL updates, and releases locks when either virtual host is missing. |
| `ssl-hostnames.t` | SSL hostname selection uses known DNS records without resolver lookups, preserves fallback for other names, and excludes unconditional redirects. Runs without networking. |
| `apache-clone-vm.t` | Real Apache directive preservation, missing-vhost lock cleanup, document roots, and PHP-FPM requests during cloning. Requires an explicit opt-in on a disposable Virtualmin Apache VM. |
| `post-actions.t` | Post-action status reporting, callback compatibility, filtering and deduplication, plus Apache backend errors and restart lock cleanup. Runs without host changes. |
| `clone-post-actions-vm.t` | Clone exit status after hook, Apache configuration, reload command and post-action failures. Checks a successful HTTP clone and fixture cleanup on an explicitly opted-in disposable Apache VM. |
| `clone-domain-exit.t` | Feature, plugin, post-action and after-clone command failures reach the CLI exit status. Covers empty, successful and partially failed database clones, legacy return values, and cleanup. Runs with in-memory fixtures and no host changes. |
| `webmin-clone.t` | Webmin language and theme copying, source preservation, unrelated account settings, inherited defaults and missing users. Runs without host changes. |
| `webmin-clone-vm.t` | Real CLI clones inherit Webmin preferences without overwriting the source user. Requires an explicit opt-in on a disposable Virtualmin VM. |
| `postgres-clone-vm.t` | Real PostgreSQL cloning with no databases, copied table data, and a database name clash. Verifies exit status and fixture cleanup. Requires an explicit opt-in on a disposable Virtualmin PostgreSQL VM. |
| `mysql-clone-vm.t` | Real MySQL/MariaDB cloning with no databases, copied table data, allowed hosts, and failures during naming, dumping and importing. Verifies exit status and fixture cleanup. Requires an explicit opt-in on a disposable Virtualmin MySQL/MariaDB VM. |
| `btrfs-lib.t` | Btrfs qgroup unit conversion, mount-path mapping, hierarchy repair, and safe subvolume lifecycle behavior. |
| `configure-commands.t` | Preferred command names, hidden repository alias, live download progress, argument forwarding, help and API access. |
| `configure-swap.t` | Swap CLI arguments, administrator access, noninteractive execution, exit status and signal handling, and the shared downloader's address selection, cleanup and forced modes. |
| `get-command.t` | Help parsing for plain, quoted and angle-bracketed values, required groups, alternatives and repetition. |
| `mailserver-restore.t` | Mail settings restores preserve the destination's Postfix SASL configuration path, including custom paths and older backups without the setting. |
| `mysql-backup-options.t` | Automatic MySQL point-in-time recovery coordinates, including binary log detection, dump client compatibility, Webmin backup API propagation, and restore-time coordinate parsing and log selection. |
| `restore-preflight.t` | Restore preflight honors UID/GID reallocation and destination DNS settings while preserving database ownership, account-name, parent, and reseller checks. |
| `module-config-write.t` | Locked module config updates preserve settings saved by concurrent processes. |
| `domain-config-write.t` | Domain key and diff updates, deleted records, lock ownership, login collection, IP-update snapshots, and final certificate metadata saves. |
| `domain-config-vm.t` | Concurrent domain writes and real CLI operations on an explicitly opted-in disposable Virtualmin VM. |
| `module-config-returns.t` | Config writer call sites treat the public keyed and diff helpers as void operations. |
| `scripts-lib.t` | PHP extension package-name generation across supported package manager families. |
| `servers-input.t` | Widget selection, grouped child folding, missing-parent visibility, IDN labels, optional list settings and administrator selection saving. |
| `server-selection.t` | Server selection parsing across bulk actions and schedules, including exclusions, repeated fields and domain access checks. |
| `wizard-lib.t` | Post-install database wizard handling for PostgreSQL initialization and startup. |

## Script Testing Guidance

Many Virtualmin scripts mix helper subs with executable file-scope code that
opens Webmin configuration, reads `/etc/webmin/virtual-server/*`, talks to
databases, or runs command-line work. Tests should avoid making those scripts
loadable by wrapping their whole executable bodies in environment-variable
guards.

Prefer one of these approaches when adding unit tests for script helpers:

1. Move reusable helper logic into an existing library file such as
   `virtual-server-lib-funcs.pl`, or a focused helper module if there is a
   clear ownership boundary.
2. Keep the script as the command entry point and test the extracted helper
   directly from the library.
3. Stub side-effecting subs under `no warnings 'redefine'` inside the test, and
   populate package globals (`%config`, `%text`, `%access`, etc.) directly when
   the helper contract needs them.

This keeps production script execution explicit and avoids changing cron,
Webmin, or CGI behavior just to make a future test possible.

## Coverage Policy

- **Tier 1: security-critical paths.** ACL checks (`acl_security.pl`, `can_*`
  predicates in `virtual-server-lib-funcs.pl`), backup encryption/key handling,
  command execution wrappers, and user/password handling should get focused
  contract tests as they are audited or changed.
- **Tier 2: active refactor surface.** New code and code changing in response
  to an audit should get targeted tests for the behavior being changed.
- **Tier 3: everything else.** Covered by `compile.t`; do not chase line
  coverage on stable script bodies without a concrete risk.

The useful goals are:

- Every parser round-trips its serializer.
- Every privilege boundary has a test.
- Every external-command call has a mock-driven test for its output parser.

## Caveats

- `VIRTUALMIN_COMPILE_T_STRICT=1` turns missing-CPAN-module skips into
  failures. Use this in CI on a fully provisioned image; leave it off on dev
  boxes where optional deps may be missing.
- `.pl` is also the Polish translation suffix. `compile.t` skips `<file>.pl`
  when a sibling `<file>` exists, so `module.info.pl` and similar data files
  are excluded without a hardcoded list.
- `perl -c` still runs compile-time Perl code, including `BEGIN` blocks and
  `use` statements. Keep compile-time side effects out of scripts and libraries
  that should be safe to check this way.
- Virtualmin scripts expect to be invoked from the module directory with
  Webmin's environment (`WEBMIN_CONFIG`, `WEBMIN_VAR`). Tests that execute
  script behavior should set those up in a tempdir or test extracted helper
  logic instead.
