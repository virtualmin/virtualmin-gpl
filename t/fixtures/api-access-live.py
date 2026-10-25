#!/usr/bin/env python3
"""Exercise API accounts on a disposable Virtualmin VM, including the admin UI.

api-access-live.py(task-directory, [options...]): test the installed API.
The directory must contain api-access-account.pl. With no options, run the full
account and domain lifecycle on Pro. On GPL, this and the shortened account
modes stop with status 2 after the form checks, because they grant provisioning
commands; use --editions-only or --cli-only there. Credentials stay in the guest
and are removed during cleanup. Never run this on the workstation.

--help-only stops after checking the form and help pages.
--commands-only stops after account creation and command selection checks.
--catalog-only also checks aliases and available Pro command metadata, then
stops before domain creation. Choose only one of these shortened modes.
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
        if 'password' in key:
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
        '_created': ('Manage servers this account creates', 'controls access after creation'),
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
        status, page = request('api_access.cgi?new=1', admin=True)
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
        status, page = request('api_access.cgi?user=' + fixture['user'], admin=True)
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
    # Module initialization rejects disabled accounts before edition messages.
    status, out = request('remote.cgi?program=create-domain')
    check(status == 403 and 'restricted' in out.lower() and
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
    check(status == 403, 'CLI disable immediately blocks API requests', out)
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
    # Check that creation exposes the expected command controls and help links.
    status, page = request('api_access.cgi?new=1', admin=True)
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
    if '--help-only' in sys.argv[2:]:
        # Stop before account creation; the finally block removes the admin fixture.
        print('All API Access help checks passed.', flush=True)
        sys.exit(0)
    if not json.loads(helper_call('edition-info'))['pro']:
        # The remaining checks grant provisioning commands, which GPL refuses by
        # design before validating anything else on the form.
        print('Remaining checks need Virtualmin Pro; use --editions-only or --cli-only on GPL.',
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
    check('api_access.cgi?user=' + fixture['user'] in page,
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
    status, page = request('api_access.cgi?user=' + fixture['user'], admin=True)
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
    status, page = request('api_access.cgi?user=' + fixture['user'], admin=True)
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
    check('api_access.cgi?user=' + fixture['user'] in page,
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
    check('api_access.cgi?user=' + fixture['user'] in page,
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
    for path in ('api_access.cgi', '../rpc.cgi'):
        status, out = request(path)
        check(status == 403, 'all mode cannot access ' + path, out)
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
        check(status == 403 and 'restricted' in page.lower(),
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
    check('restricted' in page.lower() or 'session_login' in page,
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
    check('restricted' in out.lower(), 'disabled account rejects new API requests', out)
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
    check(status == 403, 'system command grant still cannot use generic RPC', out)

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
            api('delete-domain', [('domain', domain)], admin=True)
        except Exception:
            # Report domain cleanup failures without interrupting login cleanup.
            print('Cleanup requires checking domain ' + domain, file=sys.stderr)
    try:
        helper_call('cleanup')
    finally:
        # Remove the credential file even when helper cleanup reports a failure.
        fixture_file.unlink(missing_ok=True)
