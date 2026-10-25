#!/usr/bin/perl
# Check CLI parsing and policy edits without initializing Webmin on the host.
use strict;
use warnings;
use Test::More;
use FindBin;
our (%text, %access, $admin, $module_name, @api_access_commands,
     $api_access_commands_loaded, $virtualmin_remote_api, $webmin_script_type);
# Load the real policy functions without starting Webmin or reading its config.
do "$FindBin::Bin/../security-lib.pl" or die $@ || $!;
do "$FindBin::Bin/../commands-lib.pl" or die $@ || $!;
do "$FindBin::Bin/../api-access-lib.pl" or die $@ || $!;
open(my $fh, '<', "$FindBin::Bin/../api-account-cli.pl") or die $!;
my $source = do { local $/; <$fh> };
close($fh);
# Load function bodies only; the actual entry-point guards are tested on a VM.
$source =~ /(sub api_account_cli\n.*)/s or die 'Missing CLI functions';
eval "no strict; $1";
die $@ if $@;
$module_name = 'virtual-server';
$text{apiaccess_egone} = 'Account missing';
$admin = 1;

# master_admin(): choose a root or restricted permission context for each case.
sub master_admin { return $admin; }
# list_domains(): supply a named domain and a stable ID.
sub list_domains { return ({ id => '1', dom => 'customer.example' }); }
# list_templates(): include zero, a custom template and a deleted entry.
sub list_templates { return ({ id => '0', name => 'Default Settings' },
    { id => '9', name => 'Custom template' },
    { id => '10', name => 'Deleted template', deleted => 1 }); }
# list_plans(): duplicate names must be rejected instead of chosen arbitrarily.
sub list_plans { return ({ id => '50', name => 'Default Plan' },
    { id => '60', name => 'Duplicate' }, { id => '61', name => 'Duplicate' }); }
# get_default_plan(): provide the same configured default used by the UI.
sub get_default_plan { return { id => '50' }; }
# get_init_template(parent): keep the configured top-level template at zero.
sub get_init_template { return '0'; }

# Use a saved policy to detect settings lost during a partial edit.
my $account = { name => 'billing', real => 'Existing description', policy => {
    api_id => 'immutable', api_commands => 'virtual-server:list-domains',
    api_domains => '1', api_templates => '0', api_plans => '50',
    api_template => '0', api_plan => '50', api_created => 0, api_disabled => 0 } };
{
    no warnings qw(redefine once);
    # list_api_access_users(): return only this test's dedicated account.
    *list_api_access_users = sub { return ($account); };
}
# Use a fixed command catalog instead of scanning installed modules.
@api_access_commands = map { { name => $_, key => "virtual-server:$_" } }
    qw(list-domains create-domain);
$api_access_commands_loaded = 1;

# Root terminal listings retain CLI commands; every HTTP context rejects them.
foreach my $name (qw(create-api-account modify-api-account delete-api-account list-api-accounts)) {
    ok(can_remote($name), "$name appears in local root command listings");
    foreach my $marker (qw(REQUEST_METHOD GATEWAY_INTERFACE VIRTUALMIN_REMOTE_API)) {
        local $ENV{$marker} = '1';
        ok(!can_remote($name), "$name denied with $marker");
    }
    {
        # In-process dispatch still carries the API marker after CGI cleanup.
        local $main::virtualmin_remote_api = 1;
        ok(!can_remote($name), "$name denied in an API child");
    }
    {
        # Webmin can identify a web request even without CGI environment fields.
        local $main::webmin_script_type = 'web';
        ok(!can_remote($name), "$name denied in Webmin HTTP context");
    }
    # A non-master caller cannot delegate these commands through legacy ACLs.
    local $admin = 0;
    ok(!can_remote_as_user($name), "$name cannot be delegated");
}

# Creation resolves command names and uses the UI's configured defaults.
my $create = parse_api_account_cli('create',
    ['--name', 'new-api', '--pass-stdin', '--command', 'create-domain']);
$create->{password} = 'a' x 24;
my $params = api_account_cli_params('create', $create);
is($params->{commands}, 'virtual-server:create-domain', 'command names resolve to provider grants');
is($params->{template}, '0', 'creation uses the configured template');
is($params->{plan}, '50', 'creation uses the configured plan');
is($params->{domain_mode}, 'all', 'creation matches the UI domain default');
is($params->{password_def}, 0, 'new password is explicit');

# New policies must use the configured defaults without sharing later edits.
{
    no warnings 'redefine';
    # get_default_plan(): simulate a configured plan other than the usual one.
    local *get_default_plan = sub { return { id => '60' }; };
    # get_init_template(parent): simulate a custom top-level template.
    local *get_init_template = sub { return '9'; };
    # CLI creation must follow the same configured choices as the shared helper.
    my $defaults = default_api_access_policy();
    my $configured = api_account_cli_params('create', $create);
    is($configured->{template}, '9', 'CLI follows the configured custom template');
    is($configured->{plan}, '60', 'CLI follows the configured custom plan');
    # Changing one policy must not grant commands to the next new account.
    $defaults->{api_commands} = 'virtual-server:list-domains';
    ok(!default_api_access_policy()->{api_commands}, 'each new account starts without command grants');
    # get_default_plan(): simulate an installation without an available plan.
    local *get_default_plan = sub { return undef; };
    is(default_api_access_policy()->{api_plan}, '', 'missing default plan stays empty');
}
# The shared choices exclude deleted templates, and CLI lookup rejects them.
is_deeply([map { $_->{id} } list_api_access_resources('template')], ['0', '9'],
    'shared template catalog excludes deleted entries but keeps zero');
eval { api_account_cli_params('create', { %$create, template => '10' }) };
like($@, qr/Unknown or ambiguous template/, 'CLI cannot resolve a deleted template');

# Editing one field preserves all permissions and the immutable identity.
$params = api_account_cli_params('modify', parse_api_account_cli('modify',
    ['--name', 'billing', '--disable']));
is($params->{enabled}, 0, 'disable takes effect');
is($params->{id}, 'immutable', 'edit retains account identity');
is($params->{commands}, 'virtual-server:list-domains', 'omitted command list is retained');
is($params->{domains}, '1', 'omitted domain list is retained');
is($params->{password_def}, 1, 'omitted password stays unchanged');
ok(!exists($params->{desc}), 'omitted description stays unchanged');

# Empty include and selected lists remove command and domain grants.
$params = api_account_cli_params('modify', parse_api_account_cli('modify',
    ['--name', 'billing', '--command-mode', 'include', '--domain-mode', 'selected',
     '--desc', '', '--allowed-template', 'Custom template', '--default-template', '9']));
is($params->{commands}, '', 'empty include list revokes commands');
is($params->{domains}, '', 'empty selected list removes existing domain grants');
is($params->{templates}, '9', 'template name resolves to an ID');
is($params->{desc}, '', 'empty description explicitly clears it');

# Invalid flags must fail before any account write or password-file read.
foreach my $args (
    ['--name', 'billing', '--enable', '--disable'],
    ['--name', 'billing', '--passfile', 'x', '--pass-stdin'],
    ['--name', 'billing', '--command'],
    ['--name', 'billing', '--unknown'],
    ['--name', 'billing', '--passfile', '']) {
    eval { parse_api_account_cli('modify', $args) };
    ok($@, 'reject invalid or conflicting options');
}
# Reject missing passwords, ambiguous resources and forbidden account targets.
eval { parse_api_account_cli('create', ['--name', 'new-api']) };
like($@, qr/requires --passfile or --pass-stdin/, 'creation requires password input');
eval { api_account_cli_params('modify', {name => 'billing', plan => 'Duplicate'}) };
like($@, qr/ambiguous plan/, 'duplicate display names require an ID');
eval { api_account_cli_params('modify', {name => 'billing', commands => ['create-api-account']}) };
like($@, qr/terminal-only/, 'CLI cannot grant terminal-only commands');
eval { api_account_cli_params('delete', {name => 'root'}) };
like($@, qr/Account missing/, 'deletion cannot target ordinary Webmin users');
done_testing();
