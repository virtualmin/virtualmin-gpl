# Virtualmin test suite

This `t/` tree holds tests for virtualmin-gpl. Companion infrastructure
lives in the Webmin repo (`webmin/t/`); the patterns here mirror it.

`functional-test.pl` already provides significant integration testing, but
likely needs some work to make it usable via `prove` and in CI.

## Running tests

```sh
prove -lr t                                          # everything under t/
prove t/compile.t                                    # one test file
VIRTUALMIN_COMPILE_T_FILTER='^\./backup' prove t/compile.t   # one area
```

`prove` and `Test::More` are core; on RPM-based distros, install
`perl-Test-Harness`.

## What's here

| File | What it checks |
| --- | --- |
| `compile.t` | Every `.pl` and `.cgi` parses cleanly (`perl -c`). Catches breakage from bulk refactors without exercising every page. ~1s for the full tree (537 files). |

## The require-and-stub pattern

Most Virtualmin scripts mix sub definitions with a main body that opens
the Webmin config, reads `/etc/webmin/virtual-server/*`, talks to MySQL,
or runs CLI work. To test individual subs in isolation we `require` the
script as a library without running the main body.

Virtualmin's idiom — script body runs at file scope, helper subs are
defined alongside or below — calls for the **block-wrap** form:

```perl
#!/usr/local/bin/perl
package virtual_server;
require './virtual-server-lib.pl';   # use lines and requires stay outside

unless (caller) {

# main body: arg parsing, the actual work
while(@ARGV > 0) { ... }
...

} # end of unless (caller)

sub helper { ... }
```

The `!caller(0)` one-liner form used by Webmin's `bin/` tools (`exit
main(\@ARGV) if !caller(0);`) doesn't fit here — Virtualmin scripts
don't have a `sub main` convention.

**Which scripts are wrapped.** The vast majority of `.pl` and `.cgi`
files have no helper subs beyond `sub usage`, so wrapping them buys
nothing — there is nothing to call from a test. The scripts currently
wrapped are the ones with non-trivial helper subs we'd plausibly want to
exercise in isolation:

| File | Subs available to tests |
| --- | --- |
| `link.cgi` | preview/proxy logic: `parse_preview_request`, `open_target_connection`, `send_target_request`, `read_target_headers`, `read_browser_request_body`, `is_basic_auth_challenge`, `preflight_preview_request`, `print_preview_wrapper`, `rewrite_proxy_redirect`, `sanitize_proxy_headers`, `preview_blocker_markup`, `rewrite_html_chunk`, `require_local_preview_ip` |
| `bwgraph.cgi` | `usage_colours`, `minimum_day`, `usage_for_days` |
| `backup.pl` | `first_save_print`, `second_save_print`, `indent_save_print`, `outdent_save_print`, `backup_cbfunc` |
| `functional-test.pl` | `run_test`, `run_test_command`, `postgresql_login_commands`, `convert_to_encrypted`, `convert_to_dnscloud`, `convert_to_location`, `convert_to_atmail` |
| `quotas.pl` | `send_domain_quota_email`, `send_user_quota_email`, `send_single_user_quota_email`, `check_quota_threshold`, `check_quota_interval` |
| `upload-api-docs.pl` | `convert_to_html`, `extract_html_title`, `unique`, `indexof` |
| `check-scripts.pl` | `patch_file`, `ftp_size` |
| `lookup-domain-daemon.pl` | `handle_one_request`, `send_response` |
| `info.pl` | `recursive_info_dump`, `info_search_match` |
| `restore-config-revision.pl` | `normalize_paths`, `do_restore` |
| `list-config-revisions.pl` | `normalize_paths`, `do_list` |
| `spamtrap.pl` | `find_user_by_email`, `parse_received_header`, `clear_index_file` |
| `downgrade-licence.pl` (and the `downgrade-license.pl` symlink) | `lock_all_resellers`, `execute_command_error`, `revert_virtualmin_license_file` |

Any future script that grows a testable sub should add the same guard at
the same time.

A few of the wrapped files (`restore-config-revision.pl`,
`list-config-revisions.pl`) declare lexical `my` variables at file scope
that the subs below reference (`$etcdir` for path normalization). Those
declarations are pulled above the `unless (caller)` line so the subs
still see them when the script is `require`d for testing. Initialization
remains inside the guard, so tests can mock the values themselves.

## Sub-stubbing in tests

The canonical example lives in the Webmin repo:
`webmin/t/miniserv-http_error.t`. The pattern:

1. `require` the script. The `unless (caller)` guard skips its main body.
2. Replace side-effecting subs (disk I/O, `backquote_command`, network,
   logging) with capture-buffer overrides under `no warnings 'redefine'`.
3. Populate package globals (`%config`, `%text`, `%access`, etc.)
   directly instead of running `init_config()` and friends.
4. Call the sub under test. Assert on contract — return values,
   side-effect captures, structural properties — not on cosmetics like
   exact wording or HTML class names.

Tying tests to contract rather than rendering lets the UI evolve without
breaking the test, while still catching real regressions.

## Tiered coverage policy

- **Tier 1 — security-critical paths.** ACL checks (`acl_security.pl`,
  `can_*` predicates in `virtual-server-lib-funcs.pl`), backup
  encryption/key handling, command execution wrappers, user/password
  handling. Comprehensive contract tests as scripts come under audit.
- **Tier 2 — active refactor surface.** New code, code changing in
  response to ongoing audit. perlcritic and strict/warnings for all
  code.
- **Tier 3 — everything else.** Covered by `compile.t`. Don't chase line
  coverage on stable parsers.

The goal is not coverage-as-a-number. It's:

- Every parser round-trips its serializer.
- Every privilege boundary has a test.
- Every external-command call has a mock-driven test for its output
  parser.

## Caveats

- `VIRTUALMIN_COMPILE_T_STRICT=1` turns missing-CPAN-module skips into
  failures. Use this in CI on a fully-provisioned image; leave it off on
  dev boxes where optional deps may be missing.
- `.pl` is also the Polish translation suffix. `compile.t` skips
  `<file>.pl` when a sibling `<file>` (no extension) exists, so
  `module.info.pl` and similar data files are excluded without a
  hardcoded list.
- Virtualmin scripts expect to be invoked from the module directory
  with Webmin's environment (`WEBMIN_CONFIG`, `WEBMIN_VAR`). Tests that
  go beyond `perl -c` will need to either set those up in a tmpdir or
  stub the loaders.
