#!/usr/bin/perl
# Test API account permissions without a running Webmin installation.

use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
our (%access, @api_access_commands, $api_access_commands_loaded,
     $api_access_command, @edit_limits, @features, $module_name, @plugins,
     $virtualmin_pro);
# General policy tests use Pro; edition transitions have their own tests.
$virtualmin_pro = 1;
# Load shared permission helpers without initializing Webmin.
do "$FindBin::Bin/../security-lib.pl" or die $@ || $!;
do "$FindBin::Bin/../commands-lib.pl" or die $@ || $!;
do "$FindBin::Bin/../api-access-lib.pl" or die $@ || $!;

# list_feature_plugins(): keep the ACL fixture independent of installed plugins.
sub list_feature_plugins { return (); }
# Cover explicit grants, inherited access, creator IDs, and cyclic ancestry.
my %domains = (
	1 => { id => 1, dom => 'selected.example' },
	2 => { id => 2, parent => 1, dom => 'child.selected.example' },
	3 => { id => 3, dom => 'created.example', api_owner => 'first-id' },
	4 => { id => 4, dom => 'other.example', api_owner => 'other-id' },
	5 => { id => 5, parent => 6 },
	6 => { id => 6, parent => 5 },
);
# get_domain(id): return the in-memory domain, including cyclic test ancestry.
sub get_domain { return $domains{$_[0]}; }

# A fixed catalog separates command grants from provider discovery below.
@api_access_commands = (
	{ name => 'create-domain', key => 'virtual-server:create-domain', scoped => 1 },
	{ name => 'modify-domain', key => 'virtual-server:modify-domain', scoped => 1 },
	{ name => 'list-domains', key => 'virtual-server:list-domains', scoped => 1 },
	{ name => 'create-template', key => 'virtual-server:create-template', scoped => 0 },
	{ name => 'delete-template', key => 'virtual-server:delete-template', scoped => 0 },
	{ name => 'new-command', key => 'virtual-server:new-command', scoped => 1 },
);
$api_access_commands_loaded = 1;
%access = ( api_id => 'first-id', api_domains => '1', api_created => 1,
	api_commands => 'virtual-server:create-domain virtual-server:modify-domain virtual-server:list-domains virtual-server:create-template' );
ok(is_api_access_user(), 'recognize dedicated account');
ok(api_access_can_command('create-domain'), 'explicit command grant');
# A hand-edited allowlist must not delegate terminal-only account management.
foreach my $name (qw(create-api-account modify-api-account delete-api-account list-api-accounts)) {
	local $access{api_commands} = "virtual-server:$name";
	ok(!api_access_can_command($name), "$name cannot be granted to an API account");
}
ok(!api_access_can_command('new-command'), 'new commands denied by default');
ok(!api_access_can_command('unknown-command'), 'unknown commands denied');
# A command grant is sufficient for server-wide access, without a second flag.
ok(api_access_can_command('create-template'), 'selected server-wide command allowed');
ok(!api_access_can_command('delete-template'), 'unselected server-wide command denied');
prepare_api_access_command('list-domains', []);
ok(!api_access_system_command(), 'server-wide grant does not elevate scoped commands');
prepare_api_access_command('create-template', []);
ok(api_access_system_command(), 'system authority limited to current granted command');
# Disabling the account must revoke command, system, and domain access together.
$access{api_disabled} = 1;
ok(!api_access_can_command('create-domain'), 'disabled account denies commands');
ok(!api_access_system_command(), 'disabled account loses system authority');
ok(!api_access_can_domain($domains{1}), 'disabled account denies domains');
$access{api_disabled} = 0;

# Selected domains and creation ownership are independent grants.
ok(api_access_can_domain($domains{1}), 'selected existing domain');
ok(api_access_can_domain($domains{2}), 'child inherits parent scope');
ok(api_access_can_domain($domains{3}), 'new creation belongs to account');
ok(!api_access_can_domain($domains{4}), 'another account creation is inaccessible');
ok(!api_access_can_domain(undef), 'missing domain denied');
ok(!api_access_can_domain($domains{5}), 'malformed ancestry terminates');
# A replacement login inherits neither the old ID nor its owned-domain grant.
$access{api_id} = 'replacement-id';
ok(!api_access_can_domain($domains{3}), 'recreated login does not inherit creations');
$access{api_domains} = '*';
ok(api_access_can_domain($domains{4}), 'explicit all-domains grant');
# An empty domain list must not revoke the create-domain command grant.
$access{api_domains} = '';
ok(!api_access_can_domain($domains{1}), 'empty domain scope denies existing accounts');
ok(api_access_can_command('create-domain'), 'create-domain grant needs no existing domain');
ok(api_access_contains('0 123', 0), 'default template zero is a valid grant');
ok(!api_access_contains('*', undef), 'missing ID is never authorized');

# A command provider replacement requires a new grant, not just the same name.
$api_access_commands[0]->{key} = 'another-module:create-domain';
ok(!api_access_can_command('create-domain'), 'provider substitution denied');
$api_access_commands[0]->{key} = 'virtual-server:create-domain';

# Decode repeated values without turning embedded newlines into CLI switches.
is_deeply([api_access_request_args([
	'program=modify-domain', 'domain=a.example', 'domain=b.example',
	'desc=first%0A--post-command%0Asecond', 'json=1'], 'json')],
	['--domain', 'a.example', '--domain', 'b.example',
	 '--desc', "first\n--post-command\nsecond"],
	'multiline values remain one argument and repeated parameters work');
# Ambiguous dispatch selectors and option-shaped values must fail validation.
foreach my $raw (
	['program=list-domains', 'program=create-domain'],
	['program=list-domains', 'domain=--all-domains'],
	['program=list-domains', 'domain=a%00b'],
	['program=list-domains', '--domain=x'],
	['program=list-domains', 'domain%0A--all=x'],
	['domain=example.com']) {
	eval { api_access_request_args($raw, 'json') };
	ok($@, 'reject malformed dispatch parameters');
	}
# Plan limits cannot be replaced by caller-supplied quota flags.
foreach my $command ('create-domain', 'modify-domain') {
	foreach my $flag ('quota', 'max-dbs', 'bandwidth') {
		eval { prepare_api_access_command($command, ["--$flag", 'UNLIMITED']) };
		like($@, qr/limits from a plan/, "$command cannot override $flag");
		}
	}
eval { prepare_api_access_command('unknown-command', []) };
like($@, qr/not permitted/, 'nested dispatch must authorize command');

# Help must describe API batch options without resolving or running a child.
my ($batch_help, $batch_error) = ('', '');
{
	local *STDOUT;
	open(STDOUT, '>', \$batch_help) or die $!;
	eval { run_api_access_batch(['--help']) };
	$batch_error = $@;
}
is($batch_error, '', 'API batch help succeeds without a child command');
like($batch_help, qr/virtualmin run-api-command.*--domain.*\n.*--command/s,
	'API batch help lists supported wrapper options');

# Base capabilities support provisioning without a master or reseller identity.
@edit_limits = qw(domain users delete disable remote_api);
@features = qw(unix web webmin);
my %acl = api_access_module_acl({ api_id => 'id', api_commands => 'one' });
is($acl{noconfig}, 1, 'account is never master');
ok(!$acl{reseller}, 'account does not impersonate a reseller');
is($acl{domains}, '', 'no unrestricted legacy domain grant');
is($acl{api_commands}, 'one', 'supplied command policy is retained');
ok($acl{feature_unix}, 'API ACL enables the Unix feature');

# Exercise the real catalog with command aliases, including an alias chain.
my $catalog_dir = tempdir(CLEANUP => 1);
# module_root_directory(module): map catalog reads into the temporary fixture.
sub module_root_directory { return $_[0] =~ /\/pro$/ ? "$catalog_dir/pro" : $catalog_dir; }
# plugin_defined(module, function): declare no external plugin API in this test.
sub plugin_defined { return 0; }
# read_file_contents(path): return fixture contents without initializing Webmin.
sub read_file_contents {
	open(my $fh, '<', $_[0]) or die $!;
	local $/;
	return <$fh>;
	}
$module_name = 'virtual-server';
# Create an executable command and legacy names for alias discovery.
open(my $script, '>', "$catalog_dir/create-domain.pl") or die $!;
print $script "#!/usr/bin/perl\n\n=head1 create-domain.pl\n\nCreate a domain\n\n=cut\n";
close($script);
chmod(0755, "$catalog_dir/create-domain.pl");
# A terminal-only command and its symlink alias stay out of the selector.
open(my $cli, '>', "$catalog_dir/create-api-account.pl") or die $!;
print $cli "#!/usr/bin/perl\n\n=head1 create-api-account.pl\n\nCreate an API account.\n\n=cut\n";
close($cli);
chmod(0755, "$catalog_dir/create-api-account.pl");
symlink('create-api-account.pl', "$catalog_dir/account-alias.pl") or die $!;
symlink('create-domain.pl', "$catalog_dir/old-create.pl") or die $!;
symlink('old-create.pl', "$catalog_dir/older-create.pl") or die $!;
# Package builds may turn symlinks into identical executable copies.
open(my $copy, '>', "$catalog_dir/copied-create.pl") or die $!;
print $copy read_file_contents("$catalog_dir/create-domain.pl");
close($copy);
chmod(0755, "$catalog_dir/copied-create.pl");
# Force discovery so these assertions exercise the real catalog builder.
$api_access_commands_loaded = 0;
@api_access_commands = ();
my @catalog = list_api_access_commands();
ok(!get_api_access_command('create-api-account'), 'root CLI is absent from the permission catalog');
ok(!get_api_access_command('account-alias'), 'a root CLI alias is absent from the permission catalog');
is(scalar(@catalog), 1, 'aliases appear as one grant in the real catalog');
is(get_api_access_command('older-create')->{name}, 'create-domain', 'alias chain resolves to canonical command');
is(get_api_access_command('copied-create')->{name}, 'create-domain', 'packaged alias copy resolves to canonical command');
# Alias spellings must share both grants and denials with their target.
$access{api_commands} = '';
ok(!api_access_can_command('old-create'), 'excluded canonical command denies its alias');
ok(!api_access_can_command('copied-create'), 'excluded command denies a packaged alias copy');
$access{api_commands} = 'virtual-server:create-domain';
ok(api_access_can_command('older-create'), 'canonical grant covers aliases');
eval { prepare_api_access_command('old-create', ['--quota', 'UNLIMITED']) };
like($@, qr/limits from a plan/, 'aliases retain canonical option restrictions');
# A matching POD title alone must not merge two different implementations.
open($copy, '>>', "$catalog_dir/copied-create.pl") or die $!;
print $copy "# Different implementation\n";
close($copy);
$api_access_commands_loaded = 0;
is(get_api_access_command('copied-create')->{name}, 'copied-create',
	'different command cannot share a grant just by copying its POD title');

# Descriptions use complete opening paragraphs, regardless of source wrapping.
my @descriptions = (
	[ 'wrapped',
	  "Checks for container image updates or installs them. It does not update\n".
	  "applications installed in mounted storage. The new image may still change\n".
	  "mounted files or migrate a database when it starts.\n\n".
	  "Use C<--domain name> to select a domain.\n\n=cut\n",
	  'Checks for container image updates or installs them. It does not update '.
	  'applications installed in mounted storage. The new image may still change '.
	  'mounted files or migrate a database when it starts.' ],
	[ 'single-line', "Configure swap space.\n\n=cut\n",
	  'Configure swap space.' ],
	[ 'crlf', "List virtual servers\r\nand their owners.\r\n \t\r\n".
	  "More details follow.\r\n\r\n=cut\r\n",
	  'List virtual servers and their owners.' ],
);
foreach my $case (@descriptions) {
	# Clear the cache so each case reads its own fixture's POD.
	my ($name, $pod, $expected) = @$case;
	open(my $fh, '>', "$catalog_dir/$name.pl") or die $!;
	print $fh "#!/usr/bin/perl\n\n=head1 $name.pl\n\n$pod";
	close($fh);
	chmod(0755, "$catalog_dir/$name.pl");
	$api_access_commands_loaded = 0;
	is(get_api_access_command($name)->{desc}, $expected,
		"$name description keeps only the complete opening paragraph");
	}
done_testing();
