#!/usr/bin/perl
# Test GPL and Pro rules with the shared save service and in-memory accounts.
use strict;
use warnings;
use Test::More;
use FindBin;
our (%text, %access, $virtualmin_pro, %api_account_pro_features,
     @api_access_commands, $api_access_commands_loaded, $api_access_command,
     $module_name, $locked, %users, %policies, $writes);
do "$FindBin::Bin/../commands-lib.pl" or die $@ || $!;
do "$FindBin::Bin/../api-access-lib.pl" or die $@ || $!;
# Load only the CLI parameter builder, without its root guard or initialization.
open(my $cli, '<', "$FindBin::Bin/../api-account-cli.pl") or die $!;
my $source = do { local $/; <$cli> };
close($cli);
$source =~ /(sub api_account_cli_params\n.*?)(?=\n# list_api_accounts_cli)/s
    or die 'Missing CLI parameter builder';
eval $1;
# Stop if the extracted builder cannot be compiled into this test package.
die $@ if $@;
# Use the shipped messages so errors match the UI and HTTP API.
open(my $lang, '<', "$FindBin::Bin/../lang/en") or die $!;
while (<$lang>) {
    chomp;
    $text{$1} = $2 if /^(apiaccess_\w+)=(.*)$/;
}
close($lang);
# A fixed catalog tests canonical names and aliases without scanning providers.
$module_name = 'virtual-server';
my @gated = qw(create-domain clone-domain disable-domain enable-domain);
my @free = qw(modify-domain list-users list-domains run-api-command);
@api_access_commands = map { { name => $_, key => "$module_name:$_",
    scoped => 1, aliases => [ $_, "alias-$_" ] } } (@gated, @free);
$api_access_commands_loaded = 1;

# text(key, [values...]): expand a language key without loading Webmin.
sub text {
    my ($key, @values) = @_;
    my $message = $text{$key};
    $message =~ s/\$(\d+)/$values[$1-1]/ge;
    return $message;
}
# master_admin(): deny the simulated master role while acting as an API account.
sub master_admin { return !$access{api_id}; }
# webmin_user_api_only(): advertise support for restricting an API endpoint.
sub webmin_user_api_only { return ''; }
# require_acl(): use the stubs below instead of Webmin's user module.
sub require_acl { }
# obtain_lock_webmin(): mark the simulated lock held for write assertions.
sub obtain_lock_webmin { $locked = 1; }
# release_lock_webmin(): mark the lock released so failures can be checked too.
sub release_lock_webmin { $locked = 0; }
# reload_miniserv(): keep account tests from touching a running server.
sub reload_miniserv { }
# webmin_log(action, type, name, &details): suppress system audit writes.
sub webmin_log { }
# get_miniserv_config(&config): leave sessions disabled in the fixture.
sub get_miniserv_config { }
# list_feature_plugins(): build ACLs without installed plugins.
sub list_feature_plugins { return (); }
# unique([values...]): deduplicate grant keys while preserving selection order.
sub unique { my %seen; return grep { !$seen{$_}++ } @_; }
# list_domains(): provide no targets, including for batch authorization checks.
sub list_domains { return (); }
# list_templates(): provide the template accepted by creation validation.
sub list_templates { return ({ id => 0, name => 'Default' }); }
# list_plans(): provide the plan accepted by creation validation.
sub list_plans { return ({ id => 1, name => 'Default' }); }
# get_default_plan(): use the fixture's only plan for new accounts.
sub get_default_plan { return { id => 1 }; }
# get_init_template(subdomain): use template 0 regardless of server type.
sub get_init_template { return 0; }
# acl::list_users(): expose only the in-memory accounts created by this test.
sub acl::list_users { return values %users; }
# acl::generate_random_id(): return a fixed fixture ID instead of using entropy.
sub acl::generate_random_id { return 'fixture-identity'; }
# acl::check_password_restrictions(name, password): accept fixture passwords.
sub acl::check_password_restrictions { return undef; }
# acl::encrypt_password(password, salt): return a fake SHA-512 hash.
sub acl::encrypt_password { return '$6$fixture-hash'; }
# get_module_acl(name, module): return a copy of the in-memory policy.
sub get_module_acl { return %{$policies{$_[0]}{$_[1]} || {}}; }
# save_module_acl(&acl, name, module, [replace]): store a policy under lock.
# The optional replace flag is ignored; this stub always replaces the saved ACL.
sub save_module_acl {
    die 'Unlocked write' unless $locked;
    $policies{$_[1]}{$_[2]} = { %{$_[0]} };
    $writes++;
}
# acl::create_user(&user): record a new fixture without touching system users.
sub acl::create_user { $users{$_[0]->{name}} = { %{$_[0]} }; $writes++; }
# acl::modify_user(name, &user): replace an existing fixture record.
sub acl::modify_user { $users{$_[0]} = { %{$_[1]} }; $writes++; }
# acl::delete_user(name): remove fixture login and ACLs together.
sub acl::delete_user { delete $users{$_[0]}; delete $policies{$_[0]}; $writes++; }

# save_cli(action, &options): call the shared save service with CLI parameters.
# action is create, modify or delete; options contains parsed CLI settings.
# Return an empty string on success or the caught error on failure.
sub save_cli {
    my ($action, $opts) = @_;
    eval { save_api_access_accounts(sub { api_account_cli_params($action, $opts) }) };
    my $error = $@;
    ok(!$locked, 'save releases the account lock');
    return $error;
}
# grants(name): return the saved command list without applying edition filters.
sub grants { return $policies{$_[0]}{$module_name}{api_commands}; }

# Every restriction shares one rule and leaves ordinary terminal commands alone.
$virtualmin_pro = 0;
is_deeply([sort keys %api_account_pro_features], [sort @gated],
    'only the four listed commands require Pro for API accounts');
for my $command (@gated) {
    like(api_account_pro_message("/module/$command.pl"), qr/requires Virtualmin Pro/,
        "$command reports its Pro requirement on GPL");
    ok(!api_command_unavailable_message($command), "$command remains available through GPL's CLI");
    ok(can_remote($command), "$command remains available to ordinary master logins");
}

# Explicit Pro grants must fail before creating an account or writing ACLs.
my $name = 'api-edition-fixture-93457';
my $before = $writes || 0;
like(save_cli('create', { name => $name, password => 'x' x 32,
    commands => ['create-domain'] }), qr/requires Virtualmin Pro/,
    'GPL rejects a new account with an explicit Pro grant');
is($writes || 0, $before, 'rejected creation leaves no account or ACL');
# All mode saves the GPL catalog; later explicit grants still need validation.
is(save_cli('create', { name => $name, password => 'x' x 32,
    command_mode => 'all' }), '', 'create a GPL all-commands account');
is_deeply([sort split /\s+/, grants($name)],
    [sort map { "$module_name:$_" } @free], 'all mode saves only commands available on GPL');
for my $command (@gated) {
    my $before = $writes;
    like(save_cli('modify', { name => $name, commands => [$command] }),
        qr/requires Virtualmin Pro/, "GPL cannot add $command through the CLI");
    is($writes, $before, 'denial happens before account writes');
}
# Exclude mode removes selected commands from the GPL catalog only.
is(save_cli('modify', { name => $name, command_mode => 'exclude',
    commands => ['list-users'] }), '', 'GPL excludes from available commands');
unlike(grants($name), qr/create-domain|clone-domain|disable-domain|enable-domain|list-users/,
    'exclude does not grant Pro commands');
my $gpl_grants = grants($name);

# Upgrading alone leaves the saved command list unchanged.
$virtualmin_pro = 1;
is(save_cli('modify', { name => $name, desc => 'Upgraded' }), '',
    'upgrade permits ordinary account edits');
is(grants($name), $gpl_grants, 'upgrade does not expand stored grants');
# Saving all on Pro expands the grant and permits each canonical name and alias.
is(save_cli('modify', { name => $name, command_mode => 'all' }), '',
    'explicit all on Pro grants the full current catalog');
my $pro_grants = grants($name);
for my $command (@gated) {
    local %access = %{ $policies{$name}{$module_name} };
    ok(api_access_can_command($command), "$command can use its Pro grant");
    is(prepare_api_access_command("alias-$command", [])->{name}, $command,
        'aliases use the canonical grant');
}

# Downgraded policies can be maintained without silently removing old grants.
$virtualmin_pro = 0;
is(save_cli('modify', { name => $name, desc => 'Downgraded', enabled => 0 }), '',
    'description edits and account disabling work after downgrade');
is(grants($name), $pro_grants, 'CLI partial edits preserve stored Pro grants');
is($users{$name}{real}, 'Downgraded', 'description is saved');
ok($policies{$name}{$module_name}{api_disabled}, 'account is disabled');
# Build complete form parameters to test the service's password-change path.
# The live fixture separately checks what the UI actually submits.
my $form = api_account_cli_params('modify', { name => $name, enabled => 1,
    password => 'y' x 32 });
eval { save_api_access_accounts($form) };
is($@, '', 'full form and password change accept unchanged Pro grants');
is(grants($name), $pro_grants, 'form edit preserves stored Pro grants');
# Retained grants cannot authorize direct or nested calls through an alias.
for my $command (@gated) {
    local %access = %{ $policies{$name}{$module_name} };
    ok(!api_access_can_command($command), 'stored Pro grant is inactive on GPL');
    ok(!can_remote($command), 'can_remote denies the inactive Pro grant');
    eval { prepare_api_access_command("alias-$command", []) };
    like($@, qr/requires Virtualmin Pro/, 'dispatch rejects aliases after downgrade');
    eval { run_api_access_batch(['--test', '--command', "alias-$command"]) };
    like($@, qr/requires Virtualmin Pro/, 'batch rejects a Pro command even with no domains');
}
# The dispatcher still accepts plan flags on GPL. The live fixture checks
# the command's plan validation; this test does not execute modify-domain.
{
    local %access = %{ $policies{$name}{$module_name} };
    for my $flag (qw(--plan --apply-plan --plan-features)) {
        eval { prepare_api_access_command('modify-domain', [$flag, '1']) };
        is($@, '', "$flag remains available on GPL");
    }
}
# Revocation is allowed, but re-adding a revoked Pro grant on GPL is not.
is(save_cli('modify', { name => $name, commands => ['create-domain', 'list-users'] }),
    '', 'GPL can remove saved Pro grants');
like(save_cli('modify', { name => $name, commands => ['create-domain', 'clone-domain'] }),
    qr/requires Virtualmin Pro/, 'GPL rejects re-adding a removed Pro grant');
is(save_cli('delete', { name => $name }), '', 'GPL can delete a downgraded account');
ok(!$users{$name}, 'account is removed');
done_testing();
