#!/usr/bin/env python3
"""Exercise API accounts on a disposable Virtualmin VM, including the admin UI.

api-access-live.py(task-directory, [options...]): test the installed API.
The directory must contain api-access-account.pl. With no options, run the full
account and domain lifecycle on Pro. On GPL, this and the shortened account
modes stop with status 2 after the form checks, because they grant provisioning
commands; use --editions-only, --cli-only or --options-only there. Credentials stay in the guest
and are removed during cleanup. Never run this on the workstation.

--help-only stops after checking the form and help pages.
--commands-only stops after account creation and command selection checks.
--catalog-only also checks aliases and available Pro command metadata, then
stops before domain creation. Choose only one of these shortened modes.
--options-only tests separate API option grants with real domain
changes, quota updates and reapplication, protection, bandwidth, username changes,
password hash imports, privileged file inputs, warning badges, secret output,
web directives, custom logs, 2FA removal, home relocation and harmless root hooks.
--warnings-only runs just the extended permission checks on fresh domains.
--input-validation-only checks database options and undefined custom fields.
--cli-only tests root CLI account management and checks that HTTP calls are
rejected.
--editions-only checks command permissions, direct and batch requests, and plan
changes on GPL or Pro. It also checks forms in both themes. On GPL, it adds saved
Pro grants to simulate a downgrade without changing the VM's license.
--write-failure adds a failed account creation check for file-backed Webmin users
unless --help-only stops the run first.
"""

import base64
import html
from html.parser import HTMLParser
import http.cookiejar
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# Build isolated fixture names and keep credentials in the guest task directory.
task = Path(sys.argv[1])
fixture_file = task / 'credentials.json'
helper = task / 'api-access-account.pl'
fixture = {
    'user': 'apitest' + secrets.token_hex(4),
    'admin': 'apiadmin' + secrets.token_hex(4),
    'password': secrets.token_urlsafe(32),
    'admin_password': secrets.token_urlsafe(32),
    'domain_password': secrets.token_urlsafe(32),
}
fixture['domain'] = 'customer' + secrets.token_hex(4) + '.example.test'
fixture['outside'] = fixture['user'] + '-outside.example.test'
fixture['clone'] = 'clone' + secrets.token_hex(4) + '.example.test'
os.umask(0o077)
fixture_file.write_text(json.dumps(fixture))
# All HTTP traffic stays on the guest; administrators use a cookie session.
base = 'https://127.0.0.1:10000/virtual-server/'
context = ssl._create_unverified_context()  # Guest's loopback self-signed fixture
admin_cookies = http.cookiejar.CookieJar()
admin_opener = urllib.request.build_opener(
    urllib.request.HTTPSHandler(context=context),
    urllib.request.HTTPCookieProcessor(admin_cookies))


def helper_call(mode):
    """helper_call(mode): run a fixture operation and return its stdout."""
    result = subprocess.run(['perl', str(helper), mode, str(fixture_file)],
                            capture_output=True, text=True, timeout=60)
    if result.returncode:
        # Subprocess errors may contain fixture secrets, so redact them first.
        raise RuntimeError('Fixture ' + mode + ' failed: ' + redact(result.stdout + result.stderr))
    return result.stdout


def redact(message):
    """redact(message): remove generated passwords from diagnostic text."""
    for key, value in fixture.items():
        if 'password' in key or key == 'import_hash':
            # Preserve useful names and IDs while masking credential values.
            message = message.replace(value, '[redacted]')
    return message


def request(path, params=None, admin=False, password=None, ajax=False):
    """request(path, [params], [admin], [password], [ajax]): return status and body.

    path is relative to the API module URL. params is a mapping or a sequence
    of pairs; supplying it selects POST instead of the default GET. admin
    defaults to False. password defaults to the chosen fixture user's credential.
    Admin calls retain cookies. ajax defaults to False; True adds the theme's
    XMLHttpRequest header.
    """
    user = fixture['admin'] if admin else fixture['user']
    credential = password or fixture['admin_password' if admin else 'password']
    auth = base64.b64encode((user + ':' + credential).encode()).decode()
    url = urllib.parse.urljoin(base, path)
    headers = {
        'Authorization': 'Basic ' + auth, 'Referer': base + 'api_access.cgi',
    }
    if ajax:
        # Help popups use a POST with the standard jQuery request header.
        headers['X-Requested-With'] = 'XMLHttpRequest'
    if not admin:
        # Webmin's server-to-server agent enables Basic auth on UI paths too,
        # so a login-page redirect cannot masquerade as an authorization check.
        headers['User-Agent'] = 'Webmin API account test'
    # Keep repeated parameters in order and supply the normal form referer.
    req = urllib.request.Request(url, headers=headers,
        data=urllib.parse.urlencode(params).encode() if params is not None else None)
    try:
        response = admin_opener.open(req, timeout=180) if admin else \
            urllib.request.urlopen(req, context=context, timeout=180)
        with response:
            return response.status, response.read().decode(errors='replace')
    except urllib.error.HTTPError as error:
        # Expected authorization failures are responses for the test to inspect.
        return error.code, error.read().decode(errors='replace')


def api_only_denied(status, response):
    """api_only_denied(status, response): require Webmin's explicit API denial."""
    # Webmin's standard error page uses HTTP 200; older guards returned 403.
    return (status in (200, 403) and
            'This account can only use its assigned API' in response or
            status == 403 and 'restricted' in response.lower())


def wait_for_server():
    """wait_for_server(): wait up to 20 seconds for HTTPS after a restart."""
    deadline = time.monotonic() + 20
    while True:
        try:
            # Probe readiness without replaying authenticated or mutating calls.
            with urllib.request.urlopen(base + '../session_login.cgi',
                                        context=context, timeout=2) as response:
                response.read()
            return
        except urllib.error.HTTPError:
            # An HTTP denial still confirms that the listener is ready.
            return
        except urllib.error.URLError:
            if time.monotonic() >= deadline:
                # Stop probing once the server has had time to restart.
                raise
            time.sleep(0.25)


def check(condition, message, response=''):
    """check(condition, message, [response]): report an assertion; redact failures.

    response defaults to an empty diagnostic body.
    """
    if not condition:
        # Limit diagnostic size and remove passwords before raising the failure.
        raise AssertionError(message + ': ' + redact(response[:2000] + '\n' + response[-500:]))
    print('PASS: ' + message, flush=True)


def api(program, parameters=(), admin=False):
    """api(program, [parameters], [admin]): return command output as text.

    parameters is a sequence of name/value pairs and defaults to no flags.
    admin defaults to False, using the restricted account.
    """
    return request('remote.cgi', [('program', program), *parameters], admin=admin)[1]


class HelpPage(HTMLParser):
    """HelpPage(source): collect form fields and visible help text from HTML."""

    def __init__(self, source):
        """__init__(source): parse a form or Webmin help response string."""
        super().__init__()
        self.inputs = []
        self.links = set()
        self.heading = []
        self.text = []
        self.in_heading = False
        self.hidden = 0
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        """handle_starttag(tag, attrs): collect links and find popup content."""
        attrs = dict(attrs)
        if tag == 'input':
            # Retain form field attributes for password-control checks.
            self.inputs.append(attrs)
        if tag == 'a':
            # Collect help targets independently of their displayed labels.
            self.links.add(attrs.get('href', ''))
        if 'ui_subheading' in attrs.get('class', '').split():
            # Authentic uses this heading as the popup title.
            self.in_heading = True
        if tag in ('script', 'style'):
            # Embedded code and styles are not visible help text.
            self.hidden += 1

    def handle_endtag(self, tag):
        """handle_endtag(tag): stop collecting the heading or hidden content."""
        if tag in ('h2', 'h3', 'div'):
            # Finish the heading before collecting the explanation beneath it.
            self.in_heading = False
        if tag in ('script', 'style'):
            # Resume visible-text collection after an embedded block.
            self.hidden -= 1

    def handle_data(self, data):
        """handle_data(data): retain only text the administrator can read."""
        if self.in_heading:
            # Join heading fragments even when markup splits the title.
            self.heading.append(data)
        if not self.hidden:
            # Keep readable text for assertions, excluding scripts and styles.
            self.text.append(data)


def check_help(page):
    """check_help(page): check form links and real GET/POST help responses.

    page is the account form's HTML. Each listed topic must have its expected
    heading and explanation, including the main help page and field help.
    """
    # Check each help topic's title and a short passage that proves it loaded.
    topics = {
        '': ('API Access', 'no Unix login'),
        '_user': ('Username', 'cannot be changed after creation'),
        '_password': ('API password', 'at least 24 characters'),
        '_desc': ('Description', 'what this account is used for'),
        '_commands': ('Allowed commands', 'All three modes save the commands allowed when you click Save'),
        '_scope': ('Existing virtual servers', 'including servers created later by other accounts'),
        '_created': ('Automatically include servers this account creates',
                     'marked Automatic'),
        '_templates': ('Allowed templates', 'including ones added later'),
        '_plans': ('Allowed plans', 'no combined resource limit'),
        '_defaulttemplate': ('Default template', 'requires a default template from Allowed templates'),
        '_defaultplan': ('Default plan', 'requires a default plan from Allowed plans'),
    }
    # Require the expected help links before checking the destination pages.
    links = HelpPage(page).links
    paths = {'/help.cgi/virtual-server/api_access' + suffix for suffix in topics if suffix}
    check(paths <= links, 'account help links are present', str(paths - links))
    for suffix, (title, explanation) in topics.items():
        path = '/help.cgi/virtual-server/api_access' + suffix
        for popup in (False, True):
            # Checking status alone misses help errors returned with HTTP 200.
            status, body = request(path, params={} if popup else None,
                                   admin=True, ajax=popup)
            parsed = HelpPage(body)
            heading = ''.join(parsed.heading).strip()
            text = ' '.join(' '.join(parsed.text).split())
            check(status == 200 and heading == title and explanation in text and
                  'Missing <header> section' not in text,
                  title + (': popup POST' if popup else ': help GET'), body)


def save_policy(new=False, commands=None, enabled=True, password='',
                domain_mode='selected', domains='', delete=False, command_mode='include',
                overrides=None):
    """save_policy([new], [commands], [enabled], [password],
    [domain_mode], [domains], [delete], [command_mode], [overrides]): submit the form.

    new and delete default to False; they create or remove the fixture login.
    commands defaults to the standard test set; command_mode to include.
    An empty list grants none in include mode. enabled defaults to True.
    password defaults to empty, preserving it on edits; creation uses the
    fixture password.
    domain_mode defaults to selected and domains to no existing servers.
    overrides defaults to None and replaces individual submitted form fields.
    """
    if commands is None:
        # The standard policy covers provisioning and ordinary customer actions.
        commands = ['create-domain', 'list-domains', 'disable-domain',
                    'enable-domain', 'modify-domain', 'list-templates',
                    'list-plans', 'list-commands', 'get-command', 'run-api-command',
                    'create-database', 'clone-domain', 'enable-feature']
    # Keep defaults explicit so each save tests server-side policy validation.
    params = {
        'new': '1' if new else '0', 'name': fixture['user'], 'old': fixture['user'],
        'id': fixture.get('id', ''), 'enabled': '1' if enabled else '0',
        'password': fixture['password'] if new else password,
        'password_def': '0' if new or password else '1',
        'command_mode': command_mode, 'commands': '\n'.join(
            'virtual-server:' + command for command in commands),
        'domain_mode': domain_mode, 'domains': domains, 'created': '1',
        'template_mode': 'selected', 'templates': '0', 'template': '0',
        'plan_mode': 'selected', 'plans': fixture['allowed_plan'],
        'plan': fixture['allowed_plan'],
        'delete': '1' if delete else '',
    }
    if overrides:
        # Exercise rejected forms without weakening the standard valid policy.
        params.update(overrides)
    return request('save_api_access.cgi', params, admin=True)[1]


def account_cli(command, args=(), password=None):
    """account_cli(command, [args], [password]): run the root CLI on this VM.

    command is the subcommand name; args defaults to an empty option sequence.
    password defaults to None; when supplied, it goes only to stdin.
    Return the exit status and output with fixture passwords removed.
    """
    wrapper = shutil.which('virtualmin')
    check(bool(wrapper), 'Virtualmin CLI wrapper is installed')
    result = subprocess.run([wrapper, command, *args], input=password,
                            capture_output=True, text=True, cwd=task, timeout=120)
    return result.returncode, redact(result.stdout + result.stderr)


def check_editions():
    """check_editions(): test the installed edition through UI forms, CLI and HTTP.

    On GPL, add saved Pro grants to simulate a downgrade. Keep the VM's license
    unchanged. The driver's finally block removes fixture accounts and domains.
    """
    # Use the catalog's edition flags as the expected set for all/exclude saves.
    info = json.loads(helper_call('edition-info'))
    pro = bool(info['pro'])
    gated = ['create-domain', 'clone-domain', 'disable-domain', 'enable-domain']
    basic = ['list-domains', 'list-commands', 'get-command', 'run-api-command', 'modify-domain']
    available = {entry['key'] for entry in info['commands'] if pro or not entry['pro']}
    # Both themes show Pro badges and disable these commands only on GPL.
    for theme in ('authentic', 'gray'):
        helper_call('theme-' + theme)
        status, page = request('edit_api_access.cgi?new=1', admin=True)
        fields = {field.get('value'): field for field in HelpPage(page).inputs
                  if field.get('type') == 'checkbox'}
        # Inspect rendered fields rather than inferring their state from labels.
        for command in gated:
            field = fields.get('virtual-server:' + command)
            check(status == 200 and field is not None and
                  ('disabled' in field) == (not pro),
                  theme + ': command availability matches the edition: ' + command, page)
        check(('ui_badge' in page and '>Pro<' in page) == (not pro),
              theme + ': Pro restriction badges appear only on GPL', page)
    helper_call('theme-authentic')
    # A narrow account starts with commands available in either edition.
    page = save_policy(new=True, commands=basic)
    state = json.loads(helper_call('inspect'))
    check(state['account_exists'], 'create API account on this edition', page)
    fixture['id'] = state['api_id']
    # Validation errors must identify the failed operation without changing it.
    page = save_policy(commands=basic, password='short')
    check('Failed to save API account' in page and 'at least 24 characters' in page,
          'save errors include the operation and validation message', page)
    status, page = request('save_api_access.cgi', {'bulk': '1', 'delete': '1'},
                           admin=True)
    check('Failed to delete API accounts' in page and
          json.loads(helper_call('inspect'))['account_exists'],
          'empty bulk deletion reports its operation and preserves the account', page)
    if not pro:
        # Both public save entry points must reject explicit new Pro grants.
        for command in gated:
            page = save_policy(commands=basic + [command])
            check('requires Virtualmin Pro' in page,
                  'form rejects new GPL grant: ' + command, page)
            # The terminal account editor must enforce the same grant rule.
            status, out = account_cli('modify-api-account',
                ['--name', fixture['user'], '--command', command])
            check(status != 0 and 'requires Virtualmin Pro' in out,
                  'CLI rejects new GPL grant: ' + command, out)
    # All/exclude save only this edition's catalog, with no future Pro grants.
    for mode in ('all', 'exclude'):
        page = save_policy(commands=[], command_mode=mode)
        stored = set(json.loads(helper_call('inspect'))['api_commands'].split())
        check(stored == available, mode + ' saves this edition\'s available commands', page)
    save_policy(commands=basic + gated if pro else basic)
    # Inject inactive grants on GPL to exercise dispatch independently of saves.
    helper_call('seed-pro-grants')
    helper_call('make-pro-alias')
    stored = json.loads(helper_call('inspect'))['api_commands']
    for command in gated + [fixture['user'] + '-create-alias']:
        out = api(command, [('help', '')])
        check(('requires Virtualmin Pro' not in out and 'virtualmin ' in out)
              if pro else ('requires Virtualmin Pro' in out),
              'dispatch enforces edition for ' + command, out)
    # Account metadata and counts show only commands usable in this edition.
    out = api('list-commands', [('name-only', '')])
    for command in gated:
        check((command in out.splitlines()) == pro,
              'list-commands reflects edition for ' + command, out)
    # Command help and the account list must omit inactive grants too.
    out = api('get-command', [('command', 'create-domain')])
    check(('Exit status: 0' in out) == pro, 'get-command reflects edition', out)
    status, page = request('api_access.cgi', admin=True)
    expected = len(basic) + (len(gated) if pro else 0)
    row = re.search(r'<tr\b[^>]*>(?:(?!</tr>).)*?' + fixture['user'] +
                    r'.*?</tr>', page, re.S)
    check(row and ('data-order=\"' + str(expected) + '\"' in row[0] or
                   "data-order='" + str(expected) + "'" in row[0]),
          'account list counts only usable grants', page)
    # Post the rendered hidden field, including checked disabled entries.
    # This tests HTML and form saves, without running browser JavaScript.
    for theme in ('authentic', 'gray'):
        helper_call('theme-' + theme)
        status, page = request('edit_api_access.cgi?user=' + fixture['user'], admin=True)
        fields = HelpPage(page).inputs
        hidden = [field for field in fields if field.get('name') == 'commands'
                  and field.get('type') == 'hidden']
        check(len(hidden) == 1 and 'disabled' not in hidden[0] and
              set(hidden[0]['value'].split()) == set(stored.split()),
              theme + ': one submitted field retains all stored grants', page)
        # Changing only the description must preserve the submitted command set.
        page = save_policy(commands=[], overrides={
            'commands': hidden[0]['value'], 'desc': 'Edition fixture ' + theme})
        state = json.loads(helper_call('inspect'))
        check(state['description'] == 'Edition fixture ' + theme and
              set(state['api_commands'].split()) == set(stored.split()),
              theme + ': form save preserves inactive Pro grants', page)
    # A partial CLI edit must also retain grants while disabling the account.
    helper_call('theme-authentic')
    status, out = account_cli('modify-api-account',
        ['--name', fixture['user'], '--disable', '--desc', 'Updated edition fixture'])
    state = json.loads(helper_call('inspect'))
    check(status == 0 and state['api_disabled'] == '1' and
          set(state['api_commands'].split()) == set(stored.split()),
          'CLI can disable and edit description with inactive grants', out)
    # Disabled accounts receive the normal API denial, not an edition message.
    status, out = request('remote.cgi?program=create-domain')
    check(status == 200 and 'ERROR: You are not allowed to run' in out and
          'requires Virtualmin Pro' not in out,
          'disabled account is denied before the edition check', out)
    save_policy(commands=basic + gated)
    # Pro uses the API credential to provision; GPL uses the unchanged master API.
    out = api('create-domain', [('domain', fixture['domain']),
              ('pass', fixture['domain_password']), ('unix', ''), ('dir', ''),
              ('webmin', ''), ('plan', fixture['allowed_plan']), ('template', '0')],
              admin=not pro)
    check('Exit status: 0' in out, 'create fixture through ' +
          ('Pro API account' if pro else 'ordinary GPL master API'), out)
    domain_id = json.loads(helper_call('inspect'))['domain']['id']
    save_policy(commands=basic + gated, domains=domain_id)
    # These flags stay available on GPL, with allowed-plan validation intact.
    for flags in ([('plan', fixture['allowed_plan'])],
                  [('apply-plan', fixture['allowed_plan'])], [('plan-features', '')]):
        out = api('modify-domain', [('domain', fixture['domain']), *flags])
        check('Exit status: 0' in out, 'plan option remains available: ' + flags[0][0], out)
    # Edition availability must not bypass the account's allowed-plan selection.
    out = api('modify-domain', [('domain', fixture['domain']),
              ('plan', fixture['forbidden_plan'])])
    check('not permitted' in out, 'plan changes still enforce allowed plans', out)
    # Test actual nested execution as well as dry-run authorization.
    for dry_run in (True, False):
        out = api('run-api-command', [('domain', fixture['domain']),
                  *([('test', '')] if dry_run else []), ('command', 'disable-domain')])
        check(('Exit status: 0' in out) if pro else ('requires Virtualmin Pro' in out),
              'batch enforces edition' + (' in dry run' if dry_run else ''), out)
    if pro:
        # Restore the fixture before cloning it through the restricted credential.
        out = api('enable-domain', [('domain', fixture['domain'])])
        check('Exit status: 0' in out, 'Pro API account reactivates its server', out)
        # Cloning must also work with an explicit Pro grant.
        out = api('clone-domain', [('domain', fixture['domain']),
                  ('newdomain', fixture['clone']), ('newpass', fixture['domain_password'])])
        check('Exit status: 0' in out, 'Pro API account clones its server', out)
    # Root's CLI help must stay reachable on either edition.
    for command in gated:
        status, out = account_cli(command, ['--help'])
        check('requires Virtualmin Pro' not in out and 'virtualmin ' in out,
              'root CLI help works for ' + command, out)
    if not pro:
        # Explicit broad modes replace retained Pro grants with the GPL catalog.
        for mode in ('all', 'exclude'):
            helper_call('seed-pro-grants')
            page = save_policy(commands=[], command_mode=mode)
            check(set(json.loads(helper_call('inspect'))['api_commands'].split()) == available,
                  mode + ' replaces inactive grants with available GPL commands', page)
        # Restore inactive grants to check that they cannot prevent deletion.
        helper_call('seed-pro-grants')
    # Removing the account must work whether its Pro grants are active or not.
    status, out = account_cli('delete-api-account', ['--name', fixture['user']])
    check(status == 0 and not json.loads(helper_call('inspect'))['account_exists'],
          'delete account with retained grants', out)


def check_account_cli(form):
    """check_account_cli(form): test account management and terminal-only access.

    form is the administrator's account creation page. Cleanup uses the normal
    fixture helper even if the CLI fails partway through the lifecycle.
    """
    commands = ['create-api-account', 'modify-api-account',
                'list-api-accounts', 'delete-api-account']
    check(not any('virtual-server:' + name in html.unescape(form) for name in commands),
          'terminal-only commands are absent from the permission selector', form)
    module_root = Path(helper_call('module-root').strip())
    for name in commands:
        # Help must work alone or beside other flags, without changing accounts.
        for args in (['--help'], ['--help', '--name', fixture['user']],
                     ['--name', fixture['user'], '--help']):
            code, out = account_cli(name, args)
            check(code == 0 and 'virtualmin ' + name in out,
                  name + ' accepts help through the wrapper', out)
            # Direct Perl invocation must not depend on the wrapper fixing $0.
            result = subprocess.run(['perl', name + '.pl', *args], cwd=module_root,
                capture_output=True, text=True, timeout=30)
            out = redact(result.stdout + result.stderr)
            check(result.returncode == 0 and 'virtualmin ' + name in out,
                  name + ' accepts help with a relative script path', out)
    # Create with a pipe so the generated password never appears in argv.
    code, out = account_cli('create-api-account', ['--name', fixture['user'],
        '--pass-stdin', '--desc', 'CLI billing account', '--command', 'list-domains',
        '--domain-mode', 'selected', '--no-created', '--allowed-template', '0',
        '--default-template', '0', '--allowed-plan', fixture['allowed_plan'],
        '--default-plan', fixture['allowed_plan']], fixture['password'] + '\n')
    check(code == 0, 'root CLI creates an API account', out)
    # Confirm the saved role is restricted, then authenticate with its password.
    state = json.loads(helper_call('inspect'))
    fixture['id'] = state['api_id']
    check(state['api_only'] == 'virtual-server/remote.cgi' and state['rpc'] == '0'
          and state['noconfig'] == '1' and state['unix_user'] is None,
          'CLI creation saves the same restricted role as the UI')
    out = api('list-domains', [('name-only', '')])
    check('Exit status: 0' in out, 'CLI-created credential authenticates', out)
    # Listings must show the saved policy without any credentials.
    code, out = account_cli('list-api-accounts', ['--name', fixture['user'], '--multiline'])
    check(code == 0 and 'CLI billing account' in out and
          'virtual-server:list-domains' in out and '$6$' not in out and
          '[redacted]' not in out, 'CLI lists account details without passwords', out)
    code, out = account_cli('list-api-accounts', ['--name', fixture['user'], '--name-only'])
    check(code == 0 and out.strip() == fixture['user'], 'CLI supports name-only output', out)
    # Non-root users must be stopped before Webmin configuration is loaded.
    result = subprocess.run(['runuser', '-u', 'nobody', '--', 'perl',
        str(module_root / 'list-api-accounts.pl')],
        capture_output=True, text=True, timeout=30)
    check(result.returncode != 0 and 'only to root on the command line' in
          result.stdout + result.stderr, 'direct CLI rejects a non-root user')
    # Child processes must retain the HTTP restriction even when running as root.
    for marker in ('REQUEST_METHOD', 'VIRTUALMIN_REMOTE_API'):
        result = subprocess.run(['perl', str(module_root / 'list-api-accounts.pl')],
            env={**os.environ, marker: '1'}, capture_output=True, text=True, timeout=30)
        check(result.returncode != 0 and 'only to root on the command line' in
              result.stdout + result.stderr, 'direct CLI rejects ' + marker)
    # Neither a master HTTP login nor an API credential may invoke these tools.
    for admin in (True, False):
        for name in commands:
            out = api(name, [('help', ''), ('json', '')], admin=admin)
            result = json.loads(out)
            check(result['status'] == 'error' and 'command line' in result['error'],
                  ('master' if admin else 'API account') + ' cannot invoke ' + name, out)
        out = api('get-command', [('command', 'create-api-account')], admin=admin)
        check('Exit status: 0' not in out, 'HTTP metadata cannot run CLI account help', out)
    # The command catalog must distinguish root CLI access from master HTTP.
    code, out = account_cli('list-commands', ['--name-only'])
    check(code == 0 and all(name in out.splitlines() for name in commands),
          'root terminal command listing includes account commands', out)
    out = api('list-commands', [('name-only', '')], admin=True)
    check(not any(name in out for name in commands),
          'master HTTP command listing omits account commands', out)
    # Editing a field must preserve permissions and account identity.
    code, out = account_cli('modify-api-account', ['--name', fixture['user'],
                                                '--desc', '', '--disable'])
    after = json.loads(helper_call('inspect'))
    check(code == 0 and not after['description'] and after['api_disabled'] == '1'
          and after['api_id'] == state['api_id'] and after['api_commands'] == state['api_commands'],
          'CLI edit changes only supplied settings', out)
    status, out = request('remote.cgi?program=list-domains')
    check(status == 200 and 'ERROR: You are not allowed to run' in out,
          'CLI disable immediately blocks API requests', out)
    # Password files resolve relative to the invoking shell's working directory.
    fixture['replacement_password'] = secrets.token_urlsafe(32)
    password_file = task / 'cli-password.txt'
    try:
        password_file.write_text(fixture['replacement_password'] + '\n')
        code, out = account_cli('modify-api-account', ['--name', fixture['user'],
            '--enable', '--passfile', password_file.name])
        check(code == 0, 'CLI rotates a password using a relative file', out)
    finally:
        # Remove the password file even when rotation or its assertion fails.
        password_file.unlink(missing_ok=True)
    # Rotation must invalidate the old password and accept the replacement.
    status, out = request('remote.cgi?program=list-domains')
    check(status == 401, 'CLI password rotation revokes the old password', out)
    fixture['password'] = fixture['replacement_password']
    check('Exit status: 0' in api('list-domains'), 'replacement CLI password authenticates')
    # Validation failures must preserve the entire saved account and policy.
    state = json.loads(helper_call('inspect'))
    for args in (['--command', 'create-api-account'], ['--default-plan', fixture['forbidden_plan']],
                 ['--plan-mode', 'invalid'], ['--pass-stdin']):
        code, out = account_cli('modify-api-account', ['--name', fixture['user'], *args],
                                'short' if '--pass-stdin' in args else None)
        check(code != 0 and json.loads(helper_call('inspect')) == state,
              'invalid CLI edit leaves the account unchanged', out)
    # Selecting all commands must still exclude terminal-only account tools.
    code, out = account_cli('modify-api-account', ['--name', fixture['user'],
                                                 '--command-mode', 'all'])
    state = json.loads(helper_call('inspect'))
    check(code == 0 and not any('virtual-server:' + name in state['api_commands'].split()
          for name in commands), 'CLI all mode excludes account management commands', out)
    # Deletion must reject a normal Webmin login and revoke the API login.
    code, out = account_cli('delete-api-account', ['--name', fixture['admin']])
    check(code != 0, 'CLI cannot delete an ordinary Webmin administrator', out)
    code, out = account_cli('delete-api-account', ['--name', fixture['user']])
    check(code == 0 and not json.loads(helper_call('inspect'))['account_exists'],
          'CLI deletes only the selected API account', out)
    status, out = request('remote.cgi?program=list-domains')
    check(status == 401, 'CLI deletion revokes authentication', out)
    print('All root-only CLI account tests passed.', flush=True)


def check_option_ui(extra_entries):
    """check_option_ui(extra_entries): verify catalog entries in both themes.

    extra_entries contains the option-permission records returned by the guest.
    Check each group, dependency description and badge against that catalog.
    """
    # Check real HTML grouping and dependency tooltips in both supported themes.
    class Groups(HTMLParser):
        """Collect command groups, checkbox attributes and adjacent badges."""

        def __init__(self):
            """__init__(): start with no group or current checkbox."""
            super().__init__()
            self.heading, self.group, self.fields = False, '', {}
            self.current, self.badges = None, {}
        def handle_starttag(self, tag, attrs):
            """handle_starttag(tag, attrs): associate controls with their group."""
            attrs = dict(attrs)
            if 'data-ui-multi-heading' in attrs:
                # A group heading applies to the command rows that follow it.
                self.heading, self.group = True, ''
            if tag == 'input' and attrs.get('type') == 'checkbox':
                # Keep tooltip attributes on the actual selectable control.
                self.current = attrs.get('value')
                self.fields[self.current] = (self.group, attrs)
            if 'ui_badge' in attrs.get('class', '').split() and self.current:
                # The badge following a checkbox belongs to that permission.
                self.badges.setdefault(self.current, []).extend(attrs['class'].split())

        def handle_data(self, value):
            """handle_data(value): collect visible fragments of a group title."""
            if self.heading:
                # Icons or spans can divide the heading into separate fragments.
                self.group += value

        def handle_endtag(self, tag):
            """handle_endtag(tag): stop collecting a completed group title."""
            if tag == 'div':
                # Text in later rows must not become part of the group name.
                self.heading = False
    # Change only the fixture administrator and compare the actual form HTML.
    for theme in ('authentic', 'gray'):
        helper_call('theme-' + theme)
        status, page = request('edit_api_access.cgi?user=' + fixture['user'], admin=True)
        groups = Groups()
        groups.feed(page)
        for entry in extra_entries:
            key = entry['key']
            expected = 'Commands limited to allowed virtual servers' if entry['scoped'] else \
                       'Server-wide commands'
            check(key in groups.fields and expected in groups.fields[key][0] and
                  groups.fields[key][1].get('aria-description') == entry['desc'],
                  theme + ': correct group and tooltip for ' + entry['name'])
            badge = 'ui_badge_warning' if entry.get('warning') else 'ui_badge_info'
            check(badge in groups.badges.get(key, []),
                  theme + ': correct warning badge for ' + entry['name'])
        check(status == 200 and 'Extra permission' in page and
              'Requires modify-domain.' in page,
              theme + ': option badges and dependency tooltips are rendered')
    helper_call('theme-authentic')


def check_option_permissions():
    """check_option_permissions(): verify extra grants against real guest domains.

    Only the generated fixture domains, logins and files are changed. The outer
    finally block deletes domains even after their home directories have moved.
    """
    import pwd
    # Neither account creation path may save extra permissions on their own.
    extra_entries = [entry for entry in json.loads(helper_call('edition-info'))['commands']
                     if entry.get('virtual')]
    for entry in extra_entries:
        grant = entry['name']
        expected = grant + ' requires ' + entry['parent'].split(':', 1)[1] + ' to be allowed too.'
        page = save_policy(new=True, commands=[grant])
        check(expected in html.unescape(page) and
              not json.loads(helper_call('inspect'))['account_exists'],
              'UI rejects creating an account with only ' + grant, page)
        code, out = account_cli('create-api-account',
            ['--name', fixture['user'], '--command', grant, '--pass-stdin'],
            password=fixture['password'] + '\n')
        check(code != 0 and expected in out and
              not json.loads(helper_call('inspect'))['account_exists'],
              'CLI rejects creating an account with only ' + grant, out)
    # Create independent domains as master so the API has no creation ownership.
    for domain in (fixture['domain'], fixture['outside']):
        out = api('create-domain', [('domain', domain),
                  ('pass', fixture['domain_password']), ('unix', ''), ('dir', ''),
                  ('webmin', ''), ('web', ''), ('plan', fixture['allowed_plan']),
                  ('template', '0')], admin=True)
        check('Exit status: 0' in out, 'create isolated option-test domain', out)
    initial = json.loads(helper_call('inspect'))
    domain_id = initial['domain']['id']
    basic = ['modify-domain', 'run-api-command', 'rename-domain', 'list-commands']
    page = save_policy(new=True, commands=basic, domains=domain_id)
    state = json.loads(helper_call('inspect'))
    check(state['account_exists'] and state['api_domains'] == domain_id,
          'create API account restricted to one existing domain', page)
    fixture['id'] = state['api_id']
    check(set(state['api_commands'].split()) == {'virtual-server:' + n for n in basic},
          'ordinary command grants do not acquire extra option permissions')
    # Seed only fixture login settings; no real user's second factor is touched.
    helper_call('seed-options-2fa')
    snapshot = lambda: json.loads(helper_call('inspect-options'))
    before = snapshot()
    original_home = Path(before['domain']['home'])
    new_home = str(original_home) + '-api-options'
    check(not Path(new_home).exists(), 'home relocation destination is unused')
    marker = original_home / 'api-options-marker'
    marker.write_text('fixture home marker\n')
    # Harmless hooks prove the explicit grant can execute as root in the guest.
    hook = task / 'option-hook.py'
    hook.write_text('import os, sys\nfrom pathlib import Path\n'
                    'p = Path(__file__).parent / ("option-hook-" + sys.argv[1])\n'
                    'p.write_text(str(os.geteuid()))\n')
    pre = 'python3 ' + str(hook) + ' pre'
    post = 'python3 ' + str(hook) + ' post'
    cases = {
        'quotas': [('quota', '262144'), ('uquota', '196608')],
        '2fa': [('disable-2fa', '')],
        'home': [('home', new_home)],
        'hooks': [('pre-command', pre), ('post-command', post)],
    }
    check_option_ui(extra_entries)
    for suffix, params in cases.items():
        out = api('modify-domain', [('domain', fixture['domain']), *params])
        check('API option requires permission modify-domain-' + suffix in out and
              snapshot() == before,
              'deny ' + suffix + ' without its own permission and preserve state', out)
    check(not (task / 'option-hook-pre').exists(), 'denied hooks never execute')
    # Invalid edits must leave both the saved policy and domain state unchanged.
    stored = json.loads(helper_call('inspect'))['api_commands']
    for suffix in cases:
        grant = 'modify-domain-' + suffix
        expected = grant + ' requires modify-domain to be allowed too.'
        page = save_policy(commands=[grant], domains=domain_id)
        check(expected in html.unescape(page) and
              json.loads(helper_call('inspect'))['api_commands'] == stored,
              'UI rejects saving ' + grant + ' without its parent', page)
        code, out = account_cli('modify-api-account',
            ['--name', fixture['user'], '--command', grant])
        check(code != 0 and expected in out and
              json.loads(helper_call('inspect'))['api_commands'] == stored and
              snapshot() == before,
              'CLI rejects saving ' + grant + ' without its parent', out)
    for suffix, params in cases.items():
        grant = 'modify-domain-' + suffix
        save_policy(commands=basic + [grant], domains=domain_id)
        current = snapshot()
        out = api('modify-domain', [('domain', fixture['outside']), *params])
        check('does not exist' in out and snapshot() == current,
              suffix + ': deny an existing domain outside the account scope', out)
        # One extra permission must not unlock any of the other three options.
        other = '2fa' if suffix != '2fa' else 'quotas'
        out = api('modify-domain', [('domain', fixture['domain']), *cases[other]])
        check('API option requires permission modify-domain-' + other in out and
              snapshot() == current, suffix + ': unrelated options stay blocked', out)
        if suffix in ('home', 'hooks'):
            out = api('run-api-command', [('domain', fixture['domain']),
                      ('command', 'modify-domain'), *params])
            check('Batch commands cannot use server-wide option permissions' in out and
                  snapshot() == current, suffix + ': reject server-wide effects in batches', out)
        # Real direct execution must apply exactly the permitted change.
        out = api('modify-domain.pl', [('domain', fixture['domain']), *params])
        check('Exit status: 0' in out, suffix + ': explicit option grant succeeds', out)
        after = snapshot()
        check(not after['master'] and after['outside'] == before['outside'],
              suffix + ': preserve the outside domain and never become master')
        if suffix == 'quotas':
            check(int(after['domain']['quota']) == 262144 and
                  int(after['domain']['uquota']) == 196608,
                  'quota grant stores values above the plan limits')
            out = api('run-api-command', [('domain', fixture['domain']),
                      ('command', 'modify-domain'), ('quota', '294912')])
            check('Exit status: 0' in out and int(snapshot()['domain']['quota']) == 294912,
                  'domain batch can apply an explicitly granted quota override', out)
            out = api('modify-domain', [('domain', fixture['domain']), ('bw', '999')])
            check('modify-domain-bandwidth' in out, 'disk quota permission does not unlock bandwidth', out)
        elif suffix == '2fa':
            check(not after['domain']['twofactor'] and after['outside']['twofactor'],
                  '2FA grant clears only the permitted domain login factor')
        elif suffix == 'home':
            check(after['domain']['home'] == new_home and
                  pwd.getpwnam(after['domain']['user']).pw_dir == new_home and
                  (Path(new_home) / marker.name).read_text() == 'fixture home marker\n' and
                  not original_home.exists(),
                  'home grant moves files and updates the Unix home directory')
            out = api('rename-domain', [('domain', fixture['domain']),
                      ('new-home', str(original_home) + '-rename')])
            check('API option requires permission rename-domain-home' in out,
                  'modify home permission does not unlock rename-domain options', out)
        else:
            check((task / 'option-hook-pre').read_text() == '0' and
                  (task / 'option-hook-post').read_text() == '0',
                  'explicit hook permission runs both harmless fixture hooks as root')
        # Revoke each grant and prove it is checked again on the next request.
        save_policy(commands=basic, domains=domain_id)
        current = snapshot()
        out = api('modify-domain', [('domain', fixture['domain']), *params])
        check('API option requires permission ' + grant in out and snapshot() == current,
              suffix + ': revocation takes effect on the next request', out)
    grants = basic + ['modify-domain-' + suffix for suffix in cases]
    # Root CLI edits must accept these same virtual permission names.
    args = ['--name', fixture['user']]
    for grant in grants:
        args.extend(['--command', grant])
    code, out = account_cli('modify-api-account', args)
    check(code == 0 and set(json.loads(helper_call('inspect'))['api_commands'].split()) ==
          {'virtual-server:' + n for n in grants}, 'CLI saves all four option grants', out)
    for suffix in cases:
        out = api('modify-domain-' + suffix, [('help', '')])
        check('not allowed to run' in out, 'virtual permission cannot execute: ' + suffix, out)
    out = api('list-commands', [('name-only', '')])
    check(all('modify-domain-' + suffix not in out.splitlines() for suffix in cases),
          'virtual permissions are not advertised as executable API commands', out)
    for flag in ('passfile', 'user'):
        out = api('modify-domain', [('domain', fixture['domain']), (flag, 'unused')])
        check('API option requires permission modify-domain-' + flag in out,
              'original grants cannot use an ungranted privileged flag ' + flag, out)
    save_policy(commands=grants, domains=domain_id, enabled=False)
    current = snapshot()
    out = api('modify-domain', [('domain', fixture['domain']), *cases['quotas']])
    check('not allowed' in out and snapshot() == current,
          'disabling the account also revokes its option access', out)
    print('All separate API option permission checks passed.', flush=True)


def check_more_option_permissions():
    """check_more_option_permissions(): exercise the new grants on existing fixtures."""
    import pwd
    # Reuse the isolated domains after the original option-grant checks.
    snapshot = lambda: json.loads(helper_call('inspect-options'))
    initial = snapshot()
    domain_id = initial['domain']['id']
    original_user = initial['domain']['user']
    original_uid = pwd.getpwnam(original_user).pw_uid
    original_home = initial['domain']['home']
    basic = ['modify-domain', 'rename-domain', 'create-user', 'run-api-command', 'list-commands']
    save_policy(commands=basic, domains=domain_id)
    helper_call('seed-options-hash')
    fixture.update(json.loads(fixture_file.read_text()))
    password_hash = fixture['import_hash']
    out = api('create-user', [('domain', fixture['domain']), ('user', 'quotaprobe'),
              ('pass', fixture['domain_password']), ('quota', '8192'), ('noemail', '')], admin=True)
    check('created successfully' in out, 'create a user with a saved mailbox quota', out)
    helper_call('drift-options-quota')
    before = snapshot()
    quota_user = before['domain']['users']['quotaprobe']
    check(int(quota_user['quota']) == 1024 and int(quota_user['quota_cache']) == 8192,
          'filesystem quota differs from the saved mailbox quota')
    cases = {
        'modify-domain-bandwidth': ('modify-domain', [('bw', '1048576'), ('bw-no-disable', '')]),
        'modify-domain-protection': ('modify-domain', [('protected', '')]),
        'modify-domain-quotas-reapply': ('modify-domain', [('apply-all-quotas', '')]),
        'rename-domain-user': ('rename-domain', [('new-user', fixture['user'] + 'owner')]),
        'create-user-encpass': ('create-user', [('user', 'importprobe'),
                                ('encpass', password_hash), ('noemail', '')]),
    }
    for grant, (command, params) in cases.items():
        # Neither direct calls nor the batch wrapper can omit the extra grant.
        for program, args in ((command, params),
                              ('run-api-command', [('command', command), *params])):
            out = api(program, [('domain', fixture['domain']), *args])
            check('API option requires permission ' + grant in out and snapshot() == before,
                  grant + ': deny missing permission through ' + program, out)
    for grant, (command, params) in cases.items():
        # Both account editors must reject a permission without its own base.
        saved = json.loads(helper_call('inspect'))['api_commands']
        expected = grant + ' requires ' + command + ' to be allowed too.'
        page = save_policy(commands=[grant], domains=domain_id)
        check(expected in html.unescape(page) and
              json.loads(helper_call('inspect'))['api_commands'] == saved,
              grant + ': UI rejects the missing base command', page)
        code, out = account_cli('modify-api-account',
            ['--name', fixture['user'], '--command', grant])
        check(code != 0 and expected in out and
              json.loads(helper_call('inspect'))['api_commands'] == saved,
              grant + ': CLI rejects the missing base command', out)
        save_policy(commands=basic + [grant], domains=domain_id)
        current = snapshot()
        out = api(command, [('domain', fixture['outside']), *params])
        check('does not exist' in out and snapshot() == current,
              grant + ': cannot change an existing domain outside its scope', out)
        # A new option permission must not imply the separate quota override.
        out = api('modify-domain', [('domain', fixture['domain']), ('quota', '1')])
        check('modify-domain-quotas' in out and snapshot() == current,
              grant + ': cannot change saved disk quotas', out)
        if grant == 'rename-domain-user':
            # Existing names and account-file or shell syntax must stay invalid.
            for name in ('root', current['outside']['user'], 'bad:name', 'bad;id', '../bad', 'bad\nname', 'bad\n'):
                out = api(command, [('domain', fixture['domain']), ('new-user', name)])
                check('Exit status: 0' not in out and snapshot() == current,
                      'username validation rejects collisions and unsafe syntax', out)
            out = api(command, [('domain', fixture['domain']), ('new-home', '/etc')])
            check('API option requires permission rename-domain-home' in out and snapshot() == current,
                  'username permission does not allow custom home paths', out)
        elif grant == 'create-user-encpass':
            # Hash data must not inject fields or records, including a final newline.
            for bad_hash in (password_hash + '\n', password_hash + '\r',
                             password_hash + ':extra', password_hash + ' ', password_hash + '\0'):
                out = api(command, [('domain', fixture['domain']), ('user', 'invalidprobe'),
                          ('encpass', bad_hash), ('noemail', '')])
                check('Exit status: 0' not in out and snapshot() == current,
                      'hash validation rejects password-file delimiters', out)
        # Apply the requested change through the real API and inspect its effects.
        out = api(command, [('domain', fixture['domain']), *params])
        check('Exit status: 0' in out, grant + ': granted operation succeeds', out)
        after = snapshot()
        check(not after['master'] and after['outside'] == before['outside'],
              grant + ': preserves other domains and the non-master role')
        if grant == 'modify-domain-bandwidth':
            check(int(after['domain']['bw_limit']) == 1048576 and
                  int(after['domain']['bw_no_disable']) == 1,
                  'bandwidth grant saves the limit and suspension setting')
            batch_params = [('bw', 'NONE'), ('bw-disable', '')]
        elif grant == 'modify-domain-protection':
            check(int(after['domain']['protected']) == 1, 'protection grant protects the domain')
            batch_params = [('unprotected', '')]
        elif grant == 'modify-domain-quotas-reapply':
            user = after['domain']['users']['quotaprobe']
            check(int(user['quota']) == 8192 and int(user['quota_cache']) == 8192 and
                  after['domain']['quota'] == current['domain']['quota'],
                  'reapply restores the actual mailbox quota from its saved value', out)
            helper_call('drift-options-quota')
            batch_params = params
        elif grant == 'rename-domain-user':
            new_user = after['domain']['user']
            check(new_user == fixture['user'] + 'owner' and
                  pwd.getpwnam(new_user).pw_uid == original_uid and
                  pwd.getpwnam(new_user).pw_dir == original_home,
                  'username changes preserve the Unix identity and home directory')
            batch_params = [('auto-user', '')]
        else:
            user = after['domain']['users']['importprobe']
            check(user['hash_matches'] and user['password_matches'],
                  'imported hash is preserved and verifies the original password')
            out = api('delete-user', [('domain', fixture['domain']), ('user', 'importprobe')], admin=True)
            check('Exit status: 0' in out, 'remove the direct hash-import fixture', out)
            batch_params = params
        out = api('run-api-command', [('domain', fixture['domain']),
                  ('command', command), *batch_params])
        check('Exit status: 0' in out, grant + ': authorized domain batch succeeds', out)
        after = snapshot()
        if grant == 'modify-domain-bandwidth':
            check(not after['domain']['bw_limit'] and not int(after['domain']['bw_no_disable']),
                  'bandwidth batch removes the limit and restores automatic suspension')
        elif grant == 'modify-domain-protection':
            check(not int(after['domain']['protected']), 'protection batch removes protection')
        elif grant == 'modify-domain-quotas-reapply':
            check(int(after['domain']['users']['quotaprobe']['quota']) == 8192,
                  'quota reapplication also repairs the filesystem through a batch')
        elif grant == 'rename-domain-user':
            check(after['domain']['user'] == original_user and
                  pwd.getpwnam(original_user).pw_uid == original_uid and
                  after['domain']['home'] == original_home,
                  'automatic username selection restores the expected login without moving its home')
        else:
            check(after['domain']['users']['importprobe']['hash_matches'] and
                  after['domain']['users']['importprobe']['password_matches'],
                  'batch hash import preserves a usable password')
        # Revocation takes effect immediately, including through the batch wrapper.
        save_policy(commands=basic, domains=domain_id)
        current = snapshot()
        for program, args in ((command, params),
                              ('run-api-command', [('command', command), *params])):
            out = api(program, [('domain', fixture['domain']), *args])
            check('API option requires permission ' + grant in out and snapshot() == current,
                  grant + ': revocation blocks ' + program, out)
    grants = basic + list(cases)
    args = ['--name', fixture['user']]
    for grant in grants:
        args.extend(['--command', grant])
    code, out = account_cli('modify-api-account', args)
    check(code == 0 and set(json.loads(helper_call('inspect'))['api_commands'].split()) ==
          {'virtual-server:' + name for name in grants}, 'CLI saves all five new grants', out)
    for grant in cases:
        out = api(grant, [('help', '')])
        check('not allowed to run' in out, grant + ': cannot execute as a standalone command', out)
    save_policy(commands=grants, domains=domain_id, enabled=False)
    current = snapshot()
    for grant, (command, params) in cases.items():
        out = api(command, [('domain', fixture['domain']), *params])
        check('not allowed' in out and snapshot() == current,
              grant + ': disabled account cannot use its saved permission', out)
    print('All five additional API permission checks passed.', flush=True)


def check_warning_permissions(validation_only=False):
    """check_warning_permissions([validation_only]): exercise extra grants.

    validation_only defaults to False. True stops after database and field
    validation; otherwise also test privileged files, settings and root hooks.
    The outer finally block removes all generated accounts and domains.
    """
    import pwd
    # Build the base-command policy from the installed permission catalog.
    entries = [e for e in json.loads(helper_call('edition-info'))['commands']
               if e.get('virtual')]
    parents = sorted({e['parent'].split(':', 1)[1] for e in entries})
    basic = parents + ['run-api-command']
    initial = json.loads(helper_call('inspect'))
    if not initial['domain']:
        # The focused mode creates the same disposable domains as the full suite.
        for domain in (fixture['domain'], fixture['outside']):
            out = api('create-domain', [('domain', domain),
                      ('pass', fixture['domain_password']), ('unix', ''), ('dir', ''),
                      ('webmin', ''), ('web', ''), ('plan', fixture['allowed_plan']),
                      ('template', '0')], admin=True)
            check('Exit status: 0' in out, 'create isolated warning-test domain', out)
    # Restrict both fresh and reused fixture accounts to the same target.
    initial = json.loads(helper_call('inspect'))
    domain_id = initial['domain']['id']
    target = [('domain', fixture['domain'])]
    snapshot = lambda: json.loads(helper_call('inspect-options'))
    save_policy(new=not initial['account_exists'], commands=basic, domains=domain_id)
    fixture['id'] = json.loads(helper_call('inspect'))['api_id']
    check_option_ui(entries)
    # Free the three-user fixture plan's slots after the earlier quota/hash tests.
    for user in ('quotaprobe', 'importprobe'):
        if user in snapshot()['domain']['users']:
            # Earlier option tests already checked these temporary mailboxes.
            out = api('delete-user', target + [('user', user)], admin=True)
            check('Exit status: 0' in out, 'remove earlier mailbox fixture ' + user, out)
    hook = task / 'option-hook.py'
    if not hook.exists():
        # The harmless hook records its effective UID in the task directory.
        hook.write_text('import os, sys\nfrom pathlib import Path\n'
                        'p = Path(__file__).parent / ("option-hook-" + sys.argv[1])\n'
                        'p.write_text(str(os.geteuid()))\n')
    # Every declared option must fail before parsing or touching any resources.
    for entry in entries:
        parent = entry['parent'].split(':', 1)[1]
        for flag in entry.get('options', []):
            out = api(parent, target + [(flag[2:], 'fixture-value')])
            check('API option requires permission ' + entry['name'] in out,
                  'HTTP denies ungranted option ' + entry['name'] + ' ' + flag, out)
    # A warning is metadata only; it never grants a base command or master role.
    state = json.loads(helper_call('inspect'))
    check(state['noconfig'] == '1', 'new permissions preserve the non-master role')

    def allow(*grants):
        """allow([grants...]): replace extra grants while retaining base commands."""
        save_policy(commands=basic + list(grants), domains=domain_id)

    # Grant database options without allowing them to become SQL statements.
    out = api('enable-feature', target + [('mysql', '')], admin=True)
    check('Exit status: 0' in out, 'enable MySQL on the disposable domain', out)
    allow('create-database-options')
    db_target = target + [('type', 'mysql'), ('name', 'permission_options')]
    for option, value in (('charset', 'utf8mb4;SELECT/**/1'),
                          ('collate', 'utf8mb4_general_ci;SELECT/**/1')):
        out = api('create-database', db_target + [('opt', option + ' ' + value)])
        check('Invalid MySQL ' + option + ' name' in out and 'Exit status: 0' not in out,
              'database grant rejects SQL syntax in ' + option, out)
    # Valid options must still create a database with the requested settings.
    out = api('create-database', db_target + [('opt', 'charset utf8mb4'),
              ('opt', 'collate utf8mb4_unicode_ci')])
    check('Exit status: 0' in out, 'database grant accepts valid charset and collation', out)
    match = re.search(r'Database (\S+) created successfully', out)
    check(match is not None, 'database creation reports its actual prefixed name', out)
    database = match.group(1)
    # The generated name is verified before using it in a read-only SQL query.
    check(re.fullmatch(r'[A-Za-z0-9_]+', database) is not None, 'fixture database name is safe')
    result = subprocess.run(['mysql', '-N', '-e',
        "SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME "
        "FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='" + database + "'"],
        capture_output=True, text=True, check=True, timeout=30)
    check(result.stdout.strip() == 'utf8mb4\tutf8mb4_unicode_ci',
          'new database uses the requested charset and collation')
    # The option grant must not authorize a different target domain.
    out = api('create-database', [('domain', fixture['outside']), ('type', 'mysql'),
              ('name', 'forbidden'), ('opt', 'charset utf8mb4')])
    check('Exit status: 0' not in out, 'database options cannot target an outside domain', out)
    out = api('delete-database', target + [('type', 'mysql'), ('name', database)], admin=True)
    check('Exit status: 0' in out, 'remove the extra database fixture', out)

    # Undefined field names must remain one key in the domain configuration.
    allow('modify-custom-admin-fields')
    out = api('modify-custom', target + [('allow-missing', ''),
              ('set', 'api_permissions_fixture allowed')])
    check('Exit status: 0' in out, 'custom-field grant accepts a new ordinary field', out)
    domain_file = Path('/etc/webmin/virtual-server/domains') / str(domain_id)
    check('field_api_permissions_fixture=allowed' in domain_file.read_text().splitlines(),
          'undefined custom field is saved as one configuration entry')
    # Both API parsing and direct CLI validation must reject key separators.
    for field in ('fixture=invalid', 'fixture\napi_validation_escape=1\nignored'):
        out = api('modify-custom', target + [('allow-missing', ''), ('set', field + ' value')])
        check(('Invalid custom field name' in out or
               '--set must be followed by a field name and value' in out) and
              'Exit status: 0' not in out,
              'custom-field API rejects configuration delimiters', out)
        # Separate CLI arguments reach name validation without HTTP parsing.
        result = subprocess.run(['virtualmin', 'modify-custom', '--domain', fixture['domain'],
            '--allow-missing', '--set', field, 'value'], capture_output=True,
            text=True, timeout=60)
        check(result.returncode != 0 and 'Invalid custom field name' in result.stdout,
              'custom-field CLI rejects configuration delimiters', result.stdout + result.stderr)
    check(not any(line.startswith('api_validation_escape=')
                  for line in domain_file.read_text().splitlines()),
          'invalid field input cannot add a domain configuration entry')
    if validation_only:
        # The focused rerun leaves domain deletion to the shared cleanup block.
        print('All API option input validation checks passed.', flush=True)
        return

    # Exercise a privileged server-file read with a root-owned fixture password.
    fixture['file_password'] = secrets.token_urlsafe(32)
    fixture_file.write_text(json.dumps(fixture))
    password_file = task / 'warning-password'
    password_file.write_text(fixture['file_password'] + '\n')
    password_file.chmod(0o600)
    allow('modify-domain-passfile')
    out = api('modify-domain', target + [('passfile', str(password_file))])
    check('Exit status: 0' in out, 'explicit passfile grant changes a real domain password', out)
    # Perl checks the hash inside the guest and returns only the comparison.
    check(json.loads(helper_call('inspect-warning'))['file_password_matches'],
          'domain password matches the privileged file input')
    out = api('run-api-command', target + [('command', 'modify-domain'),
              ('passfile', str(password_file))])
    check('server-wide option permissions' in out, 'batch rejects privileged password files', out)

    # Stored secret output is opt-in and limited to permitted domains.
    out = api('list-domains', target + [('multiline', '')])
    check('    Password:' not in out and '    Hashed password:' not in out,
          'ordinary domain listings hide stored credentials')
    allow('list-domains-secrets')
    out = api('list-domains', target + [('multiline', '')])
    check('    Password:' in out or '    Hashed password:' in out,
          'explicit secrets grant reveals the fixture credential')
    out = api('list-domains', [('domain', fixture['outside']), ('multiline', '')])
    check('Exit status: 0' not in out and '    Password:' not in out,
          'secret output cannot target another domain', out)
    allow()
    out = api('list-domains', target + [('multiline', '')])
    check('    Password:' not in out and '    Hashed password:' not in out,
          'revoking the secrets grant hides credentials again')

    # A root-owned public-key file is read only with its separate capability.
    key_file = task / 'warning-ssh-key'
    subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key_file)],
                   check=True, timeout=30)
    public_file = Path(str(key_file) + '.pub')
    mailbox = fixture['user'] + 'box'
    allow('create-user-noappend', 'create-user-passfile', 'create-user-ssh-key-file')
    out = api('create-user', target + [('user', mailbox), ('noappend', ''), ('noemail', ''),
              ('passfile', str(password_file)), ('ssh-pubkey', str(public_file))])
    check('Exit status: 0' in out, 'create mailbox with file inputs and an unprefixed username', out)
    mailbox_info = pwd.getpwnam(mailbox)
    authorized = Path(mailbox_info.pw_dir) / '.ssh' / 'authorized_keys'
    check(public_file.read_text().strip() in authorized.read_text(),
          'mailbox receives the key from the privileged fixture file')
    # File detection happens inside the command, including a batch child.
    allow('modify-user-ssh-key-file')
    out = api('run-api-command', target + [('command', 'modify-user'),
              ('user', mailbox), ('ssh-pubkey', str(public_file))])
    check('Exit status: 0' not in out,
          'batch child denies conditional file reads even with the saved grant', out)
    out = api('modify-user', target + [('user', mailbox), ('ssh-pubkey', str(public_file))])
    check('Exit status: 0' in out, 'direct request can use its explicit SSH file grant', out)
    # Each listing has its own secrets grant; one cannot authorize the other.
    out = api('list-users', target + [('multiline', '')])
    check('    Encrypted password:' not in out, 'ordinary user listings hide password hashes')
    allow('list-users-secrets')
    out = api('list-users', target + [('multiline', '')])
    check('    Encrypted password:' in out, 'user listing reveals hashes only with its own grant')

    # Apply a harmless web directive, verify the real config, and remove it.
    allow('modify-web-directives')
    directive = 'ErrorDocument 404 /api-permission-fixture-notfound'
    out = api('modify-web', target + [('add-directive', directive)])
    check('Exit status: 0' in out, 'explicit directive grant updates the web server', out)
    out = api('get-apache-config', target, admin=True)
    check(directive in out, 'web configuration contains the granted directive', out)
    out = api('modify-web', [('domain', fixture['outside']), ('add-directive', directive)])
    check('Exit status: 0' not in out, 'privileged web grant retains target-domain checks', out)
    out = api('modify-web', target + [('remove-directive', 'ErrorDocument')])
    check('Exit status: 0' in out, 'remove the fixture web directive', out)
    out = api('modify-web', target + [('access-log', str(task / 'warning-access.log'))])
    check('modify-web-logs' in out, 'directive grant does not permit custom log paths', out)
    # The log grant must not also permit arbitrary directives.
    allow('modify-web-logs')
    out = api('modify-web', target + [('access-log', str(task / 'warning-access.log'))])
    check('Exit status: 0' in out, 'separate log grant accepts a root-managed log path', out)
    out = api('get-apache-config', target, admin=True)
    check(str(task / 'warning-access.log') in out, 'real web configuration uses the custom log path')

    # Administrator-only PHP settings still validate their names and values.
    out = api('modify-web', target + [('mode', 'fpm')], admin=True)
    check('Exit status: 0' in out, 'prepare the fixture PHP-FPM pool', out)
    allow('modify-php-ini-admin')
    php_args = [('ini-name', 'memory_limit'), ('ini-value', '193M'), ('fpm-admin-value', '')]
    out = api('modify-php-ini', target + php_args)
    check('Exit status: 0' in out and
          json.loads(helper_call('inspect-warning'))['php_admin_memory'] == '193M',
          'PHP grant writes a real administrator-only pool setting', out)
    # Permission to set admin values must not permit new configuration lines.
    out = api('modify-php-ini', target + [('ini-name', 'memory_limit'),
              ('ini-value', '193M\ninvalid=1'), ('fpm-admin-value', '')])
    check('values cannot contain newlines' in out,
          'PHP administrator grant retains configuration-injection checks', out)
    allow()
    out = api('modify-php-ini', target + php_args)
    check('modify-php-ini-admin' in out, 'PHP admin permission revocation takes effect', out)

    # Generate a fixture key on the guest; never export it in diagnostic output.
    cert_file, tls_key = task / 'warning-cert.pem', task / 'warning-key.pem'
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-subj', '/CN=' + fixture['domain'], '-days', '1',
                    '-keyout', str(tls_key), '-out', str(cert_file)],
                   capture_output=True, check=True, timeout=60)
    out = api('modify-web', target + [('break-ssl-cert', '')], admin=True)
    check('Exit status: 0' in out, 'keep the fixture certificate independent', out)
    cert_args = [('cert', str(cert_file)), ('key', str(tls_key))]
    out = api('install-cert', target + cert_args)
    check('Certificate files are only available' in out,
          'certificate file input is denied without its grant', out)
    allow('install-cert-files')
    out = api('install-cert', target + cert_args)
    check('Exit status: 0' in out, 'certificate file permission installs the guest fixture certificate', out)
    # Installing a key and exporting it require different permissions.
    out = api('list-certs', target + [('key', '')])
    check('list-certs-private-keys' in out and 'PRIVATE KEY-----' not in out,
          'install permission does not grant private-key export')
    allow('list-certs-private-keys')
    out = api('list-certs', target + [('key', '')])
    check('Exit status: 0' in out and 'PRIVATE KEY-----' in out,
          'explicit private-key grant exports the fixture key')
    out = api('run-api-command', target + [('command', 'list-certs'), ('key', '')])
    check('server-wide option permissions' in out and 'PRIVATE KEY-----' not in out,
          'domain batches cannot export shared private keys')

    # Actual username and home changes must preserve the domain's identity.
    initial = snapshot()['domain']
    original_user, original_home = initial['user'], initial['home']
    new_user = fixture['user'] + 'owner'
    allow('modify-domain-user')
    out = api('modify-domain', target + [('user', new_user)])
    check('Exit status: 0' in out and snapshot()['domain']['user'] == new_user,
          'modify-domain username permission performs a real rename', out)
    out = api('modify-domain', target + [('user', original_user)])
    check('Exit status: 0' in out, 'restore the fixture username', out)
    # Move only the disposable home, then restore it before cleanup.
    allow('rename-domain-home')
    new_home = original_home + '-warning'
    check(not Path(new_home).exists(), 'custom home test destination is unused')
    out = api('rename-domain', target + [('new-home', new_home)])
    check('Exit status: 0' in out and snapshot()['domain']['home'] == new_home,
          'rename-domain home permission moves the real fixture directory', out)
    out = api('rename-domain', target + [('new-home', original_home)])
    check('Exit status: 0' in out, 'restore the fixture home directory', out)

    # Root hooks are deliberately delegated, without giving a master role.
    hook = task / 'option-hook.py'
    allow('create-domain-hooks', 'delete-domain-hooks')
    out = api('create-domain', [('domain', fixture['clone']),
              ('pass', fixture['domain_password']), ('unix', ''), ('dir', ''),
              ('webmin', ''), ('web', ''), ('plan', fixture['allowed_plan']),
              ('template', '0'), ('post-command', 'python3 ' + str(hook) + ' create')])
    check('Exit status: 0' in out and (task / 'option-hook-create').read_text() == '0',
          'explicit creation hook executes as root on the disposable guest', out)
    out = api('delete-domain', [('domain', fixture['clone']),
              ('post-command', 'python3 ' + str(hook) + ' delete')])
    check('Exit status: 0' in out and (task / 'option-hook-delete').read_text() == '0',
          'explicit deletion hook executes as root on the disposable guest', out)
    check(json.loads(helper_call('inspect'))['noconfig'] == '1',
          'dangerous option grants never turn the account into a master administrator')
    print('All warning permission integration checks passed.', flush=True)


try:
    # Create the temporary administrator and plans before using the real form.
    helper_call('setup')
    fixture = json.loads(fixture_file.read_text())
    wait_for_server()
    # The normal UI uses sessions even when remote.cgi accepts Basic auth.
    login = urllib.request.Request(base.replace('/virtual-server/', '/session_login.cgi'),
        data=urllib.parse.urlencode({'user': fixture['admin'],
             'pass': fixture['admin_password'], 'page': '/virtual-server/api_access.cgi'}).encode(),
        headers={'Cookie': 'testing=1'})
    with admin_opener.open(login, timeout=60) as response:
        response.read()
    # The list links to the separate editor without rendering its form.
    status, page = request('api_access.cgi', admin=True)
    check(status == 200 and 'edit_api_access.cgi?new=1' in page and
          'command_mode' not in page,
          'account list links to creation without rendering the editor', page)
    # Check that creation exposes the expected command controls and help links.
    status, page = request('edit_api_access.cgi?new=1', admin=True)
    check(status == 200 and 'save_api_access.cgi' in page and 'command_mode' in page,
          'master can render account creation form', page)
    check('virtual-server:create-domain' in html.unescape(page),
          'form includes provisioning command', page)
    command_modes = re.search(r'<select\b[^>]*\bname="command_mode"[^>]*>(.*?)</select>', page, re.S)
    check(command_modes and 'value="all"' in command_modes[1],
          'command selector offers an explicit all mode', page)
    check(not re.search(r'''name=["']system["']''', page) and
          'api_access_system' not in page,
          'command permissions have no separate server-wide switch', page)
    if '--editions-only' in sys.argv[2:]:
        # This mode covers GPL and Pro without assuming provisioning is granted.
        check_editions()
        print('All API account edition checks passed.', flush=True)
        sys.exit(0)
    if '--cli-only' in sys.argv[2:]:
        # CLI testing shares the same isolated accounts and cleanup as UI tests.
        check_account_cli(page)
        sys.exit(0)
    check_help(page)
    if '--warnings-only' in sys.argv[2:] or '--input-validation-only' in sys.argv[2:]:
        # Focused runs create their own domains and share the normal cleanup.
        check_warning_permissions('--input-validation-only' in sys.argv[2:])
        sys.exit(0)
    if '--options-only' in sys.argv[2:]:
        # Exercise the original grants before the expanded permission checks.
        check_option_permissions()
        check_more_option_permissions()
        check_warning_permissions()
        sys.exit(0)
    if '--help-only' in sys.argv[2:]:
        # Stop before account creation; the finally block removes the admin fixture.
        print('All API Access help checks passed.', flush=True)
        sys.exit(0)
    if not json.loads(helper_call('edition-info'))['pro']:
        # The remaining checks grant provisioning commands, which GPL refuses by
        # design before validating anything else on the form.
        print('Remaining checks need Virtualmin Pro; use --editions-only, --cli-only or --options-only on GPL.',
              flush=True)
        sys.exit(2)
    # Only run the Pro metadata case when that command is actually installed.
    pro_command = 'virtual-server/pro:check-connectivity' in html.unescape(page)

    # Invalid new-account forms must leave no login, including a locked one.
    for label, fields, expected in (
            ('short password', {'password': 'too-short'}, 'at least 24'),
            ('missing password', {'password': '', 'password_def': '1'}, 'at least 24'),
            ('unknown command', {'commands': 'virtual-server:no-such-command'},
             'command selection is invalid'),
            ('forbidden default', {'plan': fixture['forbidden_plan']},
             'The default template and plan must be in the allowed selections'),
            ('all commands without creation defaults',
             {'command_mode': 'all', 'commands': '', 'template': ''},
             'The default template and plan must be in the allowed selections')):
        page = save_policy(new=True, overrides=fields)
        state = json.loads(helper_call('inspect'))
        check(expected in page and not state['account_exists'],
              'reject ' + label + ' without creating a login', page)

    if '--write-failure' in sys.argv[2:]:
        # A storage error must not leave an enabled account without its policy.
        helper_call('block-policy')
        try:
            page = save_policy(new=True)
            state = json.loads(helper_call('inspect'))
            check(state['account_exists'] and state['account_locked'],
                  'failed policy write leaves the new login locked', page)
            status, out = request('remote.cgi?program=list-domains')
            check(status in (401, 403), 'failed account creation cannot authenticate', out)
        finally:
            # Remove the injected write failure even if an assertion fails.
            helper_call('unblock-policy')

    # Create through the real UI handler, then inspect the saved permissions.
    page = save_policy(new=True, commands=['list-shared-addresses'])
    check('edit_api_access.cgi?user=' + fixture['user'] in page,
          'admin UI creates dedicated API account', page)
    state = json.loads(helper_call('inspect'))
    fixture['id'] = state['api_id']
    check(state['noconfig'] == '1' and state['rpc'] == '0'
          and state['api_only'] == 'virtual-server/remote.cgi' and state['unix_user'] is None,
          'credential has no master role, Unix login or generic RPC')
    # A selected server-wide command needs no extra flag and allows no others.
    out = api('list-shared-addresses')
    check('Exit status: 0' in out,
          'new account runs a selected server-wide command without another flag', out)
    # An API-only login must never fall back to an ordinary master role.
    helper_call('clear-policy')
    try:
        status, out = request('remote.cgi?program=list-shared-addresses&json=1')
        result = json.loads(out)
        check(status == 200 and result.get('status') == 'error' and
              'not allowed' in result.get('error', ''),
              'missing Virtualmin policy is denied through the API', out)
        out = api('list-shared-addresses', admin=True)
        check('Exit status: 0' in out, 'ordinary master API still works', out)
    finally:
        # Restore only the fixture policy, even if a request fails.
        helper_call('restore-policy')
    out = api('list-shared-addresses')
    check('Exit status: 0' in out, 'restored API policy works again', out)
    out = api('list-domains')
    check('ERROR:' in out, 'server-wide command selection does not allow other commands', out)
    # Rejected edits must leave the existing account's saved policy intact.
    page = save_policy(commands=['list-domains'], overrides={'id': 'wrong-account-identity'})
    check('no longer exists or has been replaced' in page and
          json.loads(helper_call('inspect')) == state,
          'stale account form cannot change saved permissions', page)
    page = save_policy(overrides={'domains': 'nonexistent-domain'})
    check('selection is invalid' in page and json.loads(helper_call('inspect')) == state,
          'invalid domain selection leaves the policy unchanged', page)

    # Descriptions must stay on one config line and render as text, not HTML.
    description = 'Billing <api> & sync'
    page = save_policy(commands=['list-shared-addresses'],
                       overrides={'desc': ' Billing <api>\r\n\0& sync '})
    state = json.loads(helper_call('inspect'))
    check(state['description'] == description and html.escape(description) in page,
          'description is normalized, saved and escaped in the account list', page)
    check(re.search(r'''data-sortable=["']1["']''', page),
          'account table requests theme sorting', page)
    check('<tt>list-shared-addresses</tt>' in page,
          'allowed command details list the saved command', page)
    save_policy(commands=['list-shared-addresses'])
    check(json.loads(helper_call('inspect'))['description'] == description,
          'an omitted description preserves the saved value')
    status, page = request('edit_api_access.cgi?user=' + fixture['user'], admin=True)
    check(any(f.get('name') == 'desc' and f.get('value') == description
              for f in HelpPage(page).inputs), 'description appears in the edit form', page)
    page = save_policy(commands=['list-shared-addresses'], overrides={'desc': '   '})
    check(not json.loads(helper_call('inspect'))['description'],
          'a blank description clears the saved value', page)
    if not state['other_descriptions']:
        # Existing accounts with descriptions must keep their column visible.
        check('Description' not in ' '.join(re.findall(r'<th\b[^>]*>(.*?)</th>', page, re.S)),
              'description column is hidden when all descriptions are blank', page)

    # The edit form must distinguish keeping a password from replacing it.
    status, page = request('edit_api_access.cgi?user=' + fixture['user'], admin=True)
    fields = HelpPage(page).inputs
    check(status == 200 and any(f.get('name') == 'password_def' and
          f.get('value') == '1' and 'checked' in f for f in fields),
          'password edit defaults to Leave unchanged', page)
    check(any(f.get('name') == 'password_def' and f.get('value') == '0' for f in fields)
          and any(f.get('name') == 'password' and f.get('type') == 'password'
                  and not f.get('value') and f.get('autocomplete') == 'new-password'
                  for f in fields),
          'Set to offers an empty masked password field', page)
    # A password manager may fill the box while Leave unchanged is selected.
    page = save_policy(commands=['list-shared-addresses'], password='ignored-autofill',
                       overrides={'password_def': '1'})
    check('edit_api_access.cgi?user=' + fixture['user'] in page,
          'Leave unchanged ignores a filled password box', page)
    out = api('list-shared-addresses')
    check('Exit status: 0' in out, 'unchanged password still authenticates', out)
    # An empty replacement must leave the old credential valid.
    page = save_policy(commands=['list-shared-addresses'], overrides={'password_def': '0'})
    check('at least 24' in page, 'Set to rejects an empty replacement password', page)
    out = api('list-shared-addresses')
    check('Exit status: 0' in out, 'rejected replacement preserves the current password', out)
    # A valid explicit replacement must revoke the old credential.
    fixture['replacement_password'] = secrets.token_urlsafe(32)
    page = save_policy(commands=['list-shared-addresses'], password=fixture['replacement_password'])
    check('edit_api_access.cgi?user=' + fixture['user'] in page,
          'Set to accepts a valid replacement password', page)
    status, out = request('remote.cgi?program=list-shared-addresses')
    check(status == 401, 'replaced password no longer authenticates', out)
    fixture['password'] = fixture['replacement_password']
    out = api('list-shared-addresses')
    check('Exit status: 0' in out, 'replacement password authenticates', out)

    # Empty and excluded selections must still revoke server-wide commands.
    save_policy(commands=[])
    out = api('list-shared-addresses')
    check('ERROR:' in out, 'empty command selection denies server-wide commands', out)
    save_policy(commands=['list-shared-addresses'], command_mode='exclude')
    out = api('list-shared-addresses')
    check('ERROR:' in out, 'exclude mode denies the selected server-wide command', out)
    out = api('list-domains', [('name-only', '')])
    check('Exit status: 0' in out, 'exclude mode still allows other commands', out)

    # All mode saves the current catalog, retaining endpoint and role limits.
    page = save_policy(commands=[], command_mode='all')
    all_state = json.loads(helper_call('inspect'))
    catalog = set(json.loads(helper_call('catalog')))
    check(catalog and set(all_state['api_commands'].split()) == catalog,
          'all mode saves every current command as an explicit grant', page)
    check(all_state['noconfig'] == '1' and all_state['rpc'] == '0'
          and all_state['api_only'] == 'virtual-server/remote.cgi',
          'all commands retain the API-only role and endpoint restriction')
    # Broad command selection still cannot open the UI or generic RPC.
    out = api('list-shared-addresses')
    check('Exit status: 0' in out, 'all mode permits a server administration command', out)
    for path in ('api_access.cgi', 'edit_api_access.cgi?new=1',
                 'edit_api_access.cgi?user=' + fixture['user'], '../rpc.cgi'):
        status, out = request(path)
        check(api_only_denied(status, out), 'all mode cannot access ' + path, out)
    # Keep the remaining tests on their original restricted command selection.
    save_policy()

    # Batch help must work both directly and through the command metadata API.
    out = api('run-api-command', [('help', '')])
    check('virtualmin run-api-command' in out and 'Exit status: 0' in out,
          'API batch help succeeds without running a child', out)
    out = api('get-command', [('command', 'run-api-command')])
    check('Exit status: 0' in out and '\ncommand\n' in out and '\ndomain\n' in out,
          'command metadata describes supported API batch options', out)

    if '--commands-only' in sys.argv[2:]:
        # These permission checks need no domains or changes to server settings.
        print('Authenticated command selection tests passed.', flush=True)
        sys.exit(0)

    if '--catalog-only' in sys.argv[2:]:
        # Use an exact copy; installed legacy names may contain different code.
        helper_call('make-alias')
        alias = fixture['user'] + '-acme-alias'
        save_policy(commands=['generate-acme-cert'])
        out = api(alias, [('help', '')])
        check('virtualmin generate-acme-cert' in out and 'ERROR:' not in out,
              'canonical command grant allows an identical alias', out)
        save_policy(commands=['generate-acme-cert'], command_mode='exclude')
        for name in ('generate-acme-cert', alias):
            out = api(name, [('help', '')])
            check('ERROR:' in out, 'excluding canonical command also denies ' + name, out)
        if pro_command:
            # Pro metadata must use the same provider as direct dispatch.
            save_policy(overrides={'commands': 'virtual-server:get-command\n'
                                   'virtual-server/pro:check-connectivity'})
            out = api('check-connectivity', [('help', '')])
            check('virtualmin check-connectivity' in out,
                  'granted Pro command resolves', out)
            out = api('get-command', [('command', 'check-connectivity')])
            check('Exit status: 0' in out and 'Description:' in out,
                  'metadata resolves a command stored only under pro', out)
        # A stale selection must not delete valid accounts from the same request.
        page = request('save_api_access.cgi',
                       [('bulk', '1'), ('delete', '1'), ('d', fixture['id']),
                        ('d', 'stale-fixture-id')], admin=True)[1]
        check('no longer exists or has been replaced' in page and
              json.loads(helper_call('inspect'))['account_exists'],
              'stale bulk selection leaves the valid account intact', page)
        request('save_api_access.cgi',
                [('bulk', '1'), ('delete', '1'), ('d', fixture['id'])], admin=True)
        status, out = request('remote.cgi?program=get-command&command=check-connectivity')
        check(not json.loads(helper_call('inspect'))['account_exists'] and status == 401,
              'bulk deletion removes the selected account and revokes authentication', out)
        print('Authenticated command alias tests passed.', flush=True)
        sys.exit(0)

    # Require denial from the actual UI and generic RPC entry points.
    for path in ('api_access.cgi', 'domain_setup.cgi', '../index.cgi',
                 '../rpc.cgi', '../xmlrpc.cgi', '../acl/index.cgi'):
        status, page = request(path)
        check(api_only_denied(status, page),
              'API credential cannot access ' + path, page)

    # Trying the normal interactive login must not open the UI either.
    api_cookies = http.cookiejar.CookieJar()
    api_browser = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=context),
        urllib.request.HTTPCookieProcessor(api_cookies))
    login = urllib.request.Request(base.replace('/virtual-server/', '/session_login.cgi'),
        data=urllib.parse.urlencode({'user': fixture['user'],
             'pass': fixture['password'], 'page': '/index.cgi'}).encode(),
        headers={'Cookie': 'testing=1'})
    try:
        with api_browser.open(login, timeout=60) as response:
            page = response.read().decode(errors='replace')
    except urllib.error.HTTPError as error:
        # Expected authorization failures are responses for the test to inspect.
        page = error.read().decode(errors='replace')
    check('This account can only use its assigned API' in page or
          'restricted' in page.lower() or 'session_login' in page,
          'interactive login does not open the Webmin UI', page)

    # Provision a new customer and check ownership, plan, template, and quotas.
    out = api('create-domain', [('domain', fixture['domain']),
              ('pass', fixture['domain_password']), ('desc', 'API fixture')])
    check('Exit status: 0' in out, 'create independent top-level domain', out)
    state = json.loads(helper_call('inspect'))
    check(state['domain']['api_owner'] == fixture['id'] and
          state['domain']['plan'] == fixture['allowed_plan'] and
          state['domain']['template'] == '0',
          'created domain retains account identity, approved plan and template')
    check(str(state['domain']['quota']) == '131072', 'creation applies plan quota', str(state))
    # The API login must consume the customer's database allowance.
    out = api('create-database', [('domain', fixture['domain']),
              ('name', 'extra'), ('type', 'mysql')])
    check('Exit status: 0' in out, 'create database within customer plan limit', out)
    out = api('create-database', [('domain', fixture['domain']),
              ('name', 'overlimit'), ('type', 'mysql')])
    check('Exit status: 0' not in out, 'enforce customer database count for API login', out)

    # An administrator-created customer supplies an outside-scope control.
    out = api('create-domain', [('domain', fixture['outside']),
              ('pass', fixture['domain_password']), ('plan', fixture['allowed_plan']),
              ('features-from-plan', ''), ('limits-from-plan', '')], admin=True)
    check('Exit status: 0' in out, 'create outside-scope control domain', out)
    out = api('list-domains', [('name-only', '')])
    check(fixture['domain'] in out and fixture['outside'] not in out,
          'domain listing contains only scoped domains', out)
    # Structured listings must retain values as well as authorized domain names.
    out = api('list-domains', [('json', '')])
    records = json.loads(out)
    check(records['status'] == 'success' and
          any(record['name'] == fixture['domain'] and record.get('values')
              for record in records['data']), 'JSON listing returns scoped structured data', out)
    out = api('disable-domain', [('domain', fixture['outside'])])
    check('Exit status: 0' not in out and 'not' in out.lower(),
          'deny changes to outside-scope domain', out)
    state = json.loads(helper_call('inspect'))
    # A temporary grant permits cloning; the clone then has its own creator ID.
    save_policy(domains=state['outside_id'])
    out = api('clone-domain', [('domain', fixture['outside']),
              ('newdomain', fixture['clone']), ('newpass', fixture['domain_password'])])
    check('Exit status: 0' in out, 'clone explicitly granted existing customer', out)
    state = json.loads(helper_call('inspect'))
    check(state['clone_owner'] == fixture['id'], 'clone is owned by the API account that created it')
    # Inspect the rendered choices with automatic access both on and off.
    for created in ('1', '0'):
        save_policy(domains=state['outside_id'], overrides={'created': created})
        page = request('edit_api_access.cgi?user=' + fixture['user'], admin=True)[1]
        fields = HelpPage(page).inputs
        rows = {field['value']: field for field in fields
                if field.get('name') == 'domains_display_item'}
        # Only automatic checks follow the switch; manual grants stay editable.
        owned = rows[state['domain']['id']]
        check(('checked' in owned) == (created == '1') and
              ('disabled' in owned) == (created == '1'),
              'created=' + created + ': owned server follows the automatic switch')
        check('checked' in rows[state['outside_id']] and
              'disabled' not in rows[state['outside_id']],
              'created=' + created + ': manual selection stays editable')
        # The submitted hidden field must contain only the manual grant.
        check(next(field['value'] for field in fields if field.get('name') == 'domains')
              == state['outside_id'], 'submitted field contains only the manual selection')
    # Revoking the source grant must leave the API account's clone visible.
    save_policy()
    out = api('list-domains', [('name-only', '')])
    check(fixture['clone'] in out and fixture['outside'] not in out,
          'revoking existing-domain grant preserves newly created clone scope', out)
    # Creation ownership permits selected lifecycle commands, not every action.
    for command in ('disable-domain', 'enable-domain'):
        out = api(command, [('domain', fixture['domain'])])
        check('Exit status: 0' in out, command + ' works for created top-level domain', out)
    out = api('delete-domain', [('domain', fixture['domain'])])
    check('ERROR:' in out, 'deny excluded command even on owned domain', out)
    # Denials must remain recognizable to structured-output clients too.
    out = api('delete-domain', [('domain', fixture['domain']), ('json', '')])
    check(json.loads(out)['status'] == 'error',
          'excluded commands return a structured JSON error', out)
    out = api('list-commands', [('name-only', '')])
    check('create-domain' in out and 'delete-domain' not in out,
          'command listing contains only granted commands', out)
    # Help requests need permission to run the described command too.
    out = api('get-command', [('command', 'create-domain')])
    check('Exit status: 0' in out and 'domain' in out,
          'command help works with restricted identity', out)
    out = api('get-command', [('command', 'delete-domain')])
    check('Exit status: 0' not in out, 'command help cannot inspect excluded commands', out)

    # Creation may not bypass resource policy or expose privileged path options.
    for option, value in (('plan', fixture['forbidden_plan']), ('template', '1'),
                          ('quota', 'UNLIMITED'), ('passfile', '/etc/shadow'),
                          ('post-command', 'touch /tmp/api-access-escape')):
        out = api('create-domain', [('domain', fixture['user'] + '-blocked.example.test'),
                  ('pass', fixture['domain_password']), (option, value)])
        check('Exit status: 0' not in out, 'deny create option ' + option, out)
    out = api('modify-domain', [('domain', fixture['domain']), ('quota', 'UNLIMITED')])
    check('ERROR:' in out, 'deny arbitrary quota override during modification', out)
    # Changing plans or enabling features must respect the same resource policy.
    out = api('modify-domain', [('domain', fixture['domain']),
              ('plan', fixture['forbidden_plan'])])
    check('not permitted' in out and
          json.loads(helper_call('inspect'))['domain']['plan'] == fixture['allowed_plan'],
          'forbidden plan change leaves the customer plan unchanged', out)
    out = api('enable-feature', [('domain', fixture['domain']), ('ssl', '')])
    check('not permitted by' in out and 'plan' in out,
          'feature changes obey the customer plan', out)
    # Plan and template listings must respect the same grants as creation.
    out = api('list-plans', [('name-only', '')])
    check(fixture['user'] + '-allowed' in out and '-forbidden' not in out,
          'plans are filtered by policy', out)
    out = api('list-templates', [('name-only', '')])
    check('Exit status: 0' in out and 'sub-servers' not in out.lower(),
          'templates are filtered by policy', out)

    # Reject ambiguous dispatch and keep multiline text from becoming switches.
    out = request('remote.cgi', [('program', 'list-domains'),
                  ('program', 'delete-domain'), ('domain', fixture['domain'])])[1]
    check('ERROR:' in out, 'reject duplicate program parameters', out)
    out = api('modify-domain', [('domain', fixture['domain']),
              ('desc', 'Multiline\n--post-command\ntouch /tmp/api-access-escape')])
    check(not Path('/tmp/api-access-escape').exists(),
          'multiline values cannot inject a root command', out)

    # Wrappers must reauthorize the child and preserve its domain restrictions.
    out = api('run-api-command', [('domain', fixture['domain']),
              ('command', 'delete-domain')])
    check('not permitted' in out, 'batch wrapper cannot call excluded commands', out)
    out = api('run-api-command', [('domain', fixture['outside']),
              ('command', 'disable-domain')])
    check('Domain is not permitted' in out,
          'batch wrapper cannot target an outside-scope domain', out)
    out = api('run-api-command', [('domain', fixture['domain']),
              ('command', 'disable-domain')])
    check('Exit status: 0' in out, 'batch wrapper preserves authorized domain access', out)
    out = api('enable-domain', [('domain', fixture['domain'])])
    check('Exit status: 0' in out, 'restore domain after batch test', out)

    # Disable and password rotation must take effect on subsequent requests.
    page = save_policy(enabled=False)
    out = api('list-domains')
    check('ERROR: You are not allowed to run' in out,
          'disabled account rejects new API requests', out)
    new_password = secrets.token_urlsafe(32)
    page = save_policy(password=new_password)
    status, out = request('remote.cgi?program=list-domains')
    check(status == 401 or 'login' in out.lower(), 'rotation revokes old credential', out)
    fixture['password'] = new_password
    out = api('list-domains')
    check('Exit status: 0' in out, 'rotated credential works', out)

    # Exclude mode saves explicit grants for both scoped and server-wide commands.
    save_policy(commands=['delete-domain'], command_mode='exclude')
    out = api('delete-domain', [('domain', fixture['domain'])])
    check('ERROR:' in out, 'exclude selection mode saves an effective command denial', out)

    # Return to one server-wide grant to check that it cannot broaden the role.
    page = save_policy(commands=['list-shared-addresses'])
    out = api('list-shared-addresses')
    check('Exit status: 0' in out, 'explicitly granted server command works without master role', out)
    # A server-wide command grant does not grant a master role or other commands.
    out = api('list-domains')
    check('ERROR:' in out, 'system grant does not enable excluded commands', out)
    state = json.loads(helper_call('inspect'))
    check(state['noconfig'] == '1', 'system command grant still has no master login')
    status, out = request('../rpc.cgi')
    check(api_only_denied(status, out),
          'system command grant still cannot use generic RPC', out)

    # Deletion revokes authentication before the same username is reused.
    page = save_policy(delete=True)
    status, out = request('remote.cgi?program=list-domains')
    check(status == 401 or 'login' in out.lower(), 'account deletion revokes credential', out)
    # Reusing a name must not grant the replacement login its predecessor's domains.
    fixture['password'] = secrets.token_urlsafe(32)
    page = save_policy(new=True)
    state = json.loads(helper_call('inspect'))
    check(state['api_id'] != fixture['id'], 'recreated login gets a new identity')
    out = api('list-domains', [('name-only', '')])
    check(fixture['domain'] not in out, 'recreated login cannot manage old creations', out)
    print('All authenticated API account tests passed.', flush=True)
finally:
    # Keep cleanup independent of the API account's current grants or status.
    for domain in (fixture['clone'], fixture['domain'], fixture['outside'],
                   fixture['user'] + '-blocked.example.test'):
        try:
            # A failed protection test must not prevent removal of its fixture.
            if any(mode in sys.argv[2:] for mode in ('--options-only', '--warnings-only', '--input-validation-only')):
                api('modify-domain', [('domain', domain), ('unprotected', '')], admin=True)
            api('delete-domain', [('domain', domain)], admin=True)
        except Exception:
            # Report domain cleanup failures without interrupting login cleanup.
            print('Cleanup requires checking domain ' + domain, file=sys.stderr)
    try:
        helper_call('cleanup')
    finally:
        # Remove the credential file even when helper cleanup reports a failure.
        fixture_file.unlink(missing_ok=True)
        # Remove generated keys, passwords, hooks and logs.
        if any(mode in sys.argv[2:] for mode in ('--options-only', '--warnings-only', '--input-validation-only')):
            for name in ('option-hook.py', 'option-hook-pre', 'option-hook-post',
                         'option-hook-create', 'option-hook-delete', 'warning-password',
                         'warning-ssh-key', 'warning-ssh-key.pub', 'warning-access.log',
                         'warning-cert.pem', 'warning-key.pem'):
                (task / name).unlink(missing_ok=True)
