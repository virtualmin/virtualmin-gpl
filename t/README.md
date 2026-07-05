# Virtualmin test suite

This `t/` tree holds tests for virtualmin-gpl. Companion infrastructure lives
in the Webmin repo (`webmin/t/`); the patterns here should stay compatible
with that suite where practical.

`functional-test.pl` already provides significant integration coverage, but it
is not yet a lightweight `prove` target. The tests in this directory are for
smaller checks that can run quickly during normal development and CI.

## Running tests

```sh
prove -lr t
prove t/compile.t
VIRTUALMIN_COMPILE_T_FILTER='^\./backup' prove t/compile.t
```

`prove` and `Test::More` are core Perl modules. On RPM-based distros, install
`perl-Test-Harness` if `prove` is not already available.

## Current tests

| File | What it checks |
| --- | --- |
| `compile.t` | Every discovered `.pl` and `.cgi` parses cleanly with `perl -c`. It catches syntax and compile-time module-loading breakage without running normal script bodies. |

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
