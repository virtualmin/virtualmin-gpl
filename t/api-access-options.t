#!/usr/bin/perl
# Test separate API option grants with the real catalog and batch dispatcher.
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
our ($api_access_domain_batch, %access, %text, $module_name, $virtualmin_pro, $api_access_command,
     $api_access_commands_loaded, @api_access_commands);
$module_name = 'virtual-server';
$virtualmin_pro = 1;
do "$FindBin::Bin/../security-lib.pl" or die $@ || $!;
do "$FindBin::Bin/../commands-lib.pl" or die $@ || $!;
do "$FindBin::Bin/../api-access-lib.pl" or die $@ || $!;

# Provide executable fixture commands without initializing the host's Webmin.
my $dir = tempdir(CLEANUP => 1);
my $provider = $module_name;
my @parents = qw(create-admin create-database create-domain create-user
	delete-domain delete-script disable-feature enable-feature
	generate-acme-cert install-cert install-script list-admins
	list-certs list-domains list-scripts list-users
	modify-admin modify-custom modify-dns modify-domain
	modify-mail modify-php-ini modify-spam modify-user
	modify-web rename-domain start-stop-script);
my %aliases = map { ("$_-alias", $_) } @parents;
foreach my $name (@parents) {
	open(my $fh, '>', "$dir/$name.pl") or die $!;
	close($fh);
	chmod(0700, "$dir/$name.pl") or die $!;
	}
# module_root_directory(provider): return the isolated catalog directory.
sub module_root_directory { return $dir; }
# list_api_commands(): include an alias and permit provider replacement tests.
{
	no warnings qw(redefine once);
	*list_api_commands = sub {
		return map { { name => $_,
			canonical => $aliases{$_} || $_,
			provider => $provider, desc => 'Fixture command.',
			path => "$dir/".($aliases{$_} || $_).'.pl' } }
			(@parents, keys %aliases);
		};
	}
# plugin_defined(provider, function): no fixture plugin declares domain access.
sub plugin_defined { return 0; }
# text(key, command): substitute the real tooltip dependency.
sub text { my ($key, $command) = @_; my $v = $text{$key} || $key;
	$v =~ s/\$1/$command/g; return $v; }
# Supply real tooltip text so missing language entries fail the catalog tests.
open(my $lang, '<', "$FindBin::Bin/../lang/en") or die $!;
while (<$lang>) {
	chomp;
	my ($key, $value) = split(/=/, $_, 2);
	$text{$key} = $value if (defined($key) && $key =~ /^apiaccess_option_/);
	}
close($lang);
my %domain = (id => 1, dom => 'allowed.example');
# get_domain_by(field, value): resolve the one permitted batch fixture.
sub get_domain_by { return $_[1] eq $domain{dom} ? \%domain : undef; }
# get_domain(id): there are no parent domains in this fixture.
sub get_domain { return undef; }
# execute_webmin_script(): every batch here is denied or a dry run.
sub execute_webmin_script { die "Unexpected command execution\n"; }
my %options = (
	'modify-domain-quotas' => [ 'modify-domain', 1, '--quota', '--uquota' ],
	'modify-domain-quotas-reapply' => [ 'modify-domain', 1, '--apply-all-quotas' ],
	'modify-domain-bandwidth' =>
		[ 'modify-domain', 1, '--bw', '--bw-disable', '--bw-no-disable' ],
	'modify-domain-protection' => [ 'modify-domain', 1, '--protected', '--unprotected' ],
	'modify-domain-2fa' => [ 'modify-domain', 1, '--disable-2fa' ],
	'modify-domain-home' => [ 'modify-domain', 0, '--home' ],
	'modify-domain-hooks' => [ 'modify-domain', 0, '--pre-command', '--post-command' ],
	'rename-domain-user' => [ 'rename-domain', 1, '--new-user', '--auto-user' ],
	'create-user-encpass' => [ 'create-user', 1, '--encpass' ],
);
# Provisioning and ownership grants must stay tied to their base command.
$options{'create-domain-reseller'} = [ 'create-domain', 0, '--reseller' ];
$options{'create-domain-jail'} = [ 'create-domain', 1, '--enable-jail', '--disable-jail' ];
$options{'create-domain-database-server'} = [ 'create-domain', 0, '--mysql-server', '--postgres-server' ];
$options{'create-domain-passfile'} = [ 'create-domain', 0, '--passfile' ];
$options{'modify-domain-reseller'} = [ 'modify-domain', 0, '--reseller', '--add-reseller', '--delete-reseller' ];
$options{'modify-domain-jail'} = [ 'modify-domain', 1, '--enable-jail', '--disable-jail', '--copy-jail' ];
$options{'modify-domain-database-server'} = [ 'modify-domain', 0, '--mysql-server' ];
$options{'modify-domain-passfile'} = [ 'modify-domain', 0, '--passfile' ];
# Privileged file inputs are server-wide even when the target is restricted.
$options{'create-user-passfile'} = [ 'create-user', 0, '--passfile' ];
$options{'modify-user-passfile'} = [ 'modify-user', 0, '--passfile' ];
$options{'create-admin-passfile'} = [ 'create-admin', 0, '--passfile' ];
$options{'modify-admin-passfile'} = [ 'modify-admin', 0, '--passfile' ];
$options{'create-domain-ssh-key-file'} = [ 'create-domain', 0 ];
$options{'create-user-ssh-key-file'} = [ 'create-user', 0, '--ssh-pubkey-id' ];
$options{'modify-user-ssh-key-file'} = [ 'modify-user', 0, '--ssh-pubkey-id' ];
# Root hooks and home paths are separate from account-name changes.
$options{'create-domain-hooks'} = [ 'create-domain', 0, '--pre-command', '--post-command' ];
$options{'delete-domain-hooks'} = [ 'delete-domain', 0, '--pre-command', '--post-command' ];
$options{'rename-domain-home'} = [ 'rename-domain', 0, '--new-home' ];
$options{'modify-domain-user'} = [ 'modify-domain', 1, '--user' ];
$options{'create-user-noappend'} = [ 'create-user', 1, '--noappend' ];
# Shared DNS and custom-field settings need their own grant keys.
$options{'create-domain-dns-placement'} = [ 'create-domain', 0, '--no-slaves', '--no-secondaries', '--separate-dns-subdomain', '--any-dns-subdomain' ];
$options{'create-domain-admin-fields'} = [ 'create-domain', 0 ];
$options{'modify-custom-admin-fields'} = [ 'modify-custom', 0, '--allow-missing' ];
$options{'modify-mail-autoconfig'} = [ 'modify-mail', 1, '--autoconfig', '--no-autoconfig' ];
$options{'modify-mail-dkim-file'} = [ 'modify-mail', 0, '--dkim-key' ];
$options{'modify-dns-slaves'} = [ 'modify-dns', 0, '--add-slave', '--remove-slave', '--add-all-slaves', '--sync-all-slaves' ];
$options{'modify-dns-subdomain'} = [ 'modify-dns', 0, '--enable-subdomain', '--disable-subdomain' ];
# Scanner, certificate, PHP and database options retain independent grants.
$options{'modify-spam-scanners'} = [ 'modify-spam', 1, '--use-spamc', '--use-spamassassin', '--use-clamscan', '--use-clamdscan', '--use-clamd-stream-client', '--use-clamdscan-remote' ];
$options{'generate-acme-cert-email-master'} = [ 'generate-acme-cert', 1, '--email-master', '--no-email-master' ];
$options{'install-cert-files'} = [ 'install-cert', 0 ];
$options{'modify-php-ini-admin'} = [ 'modify-php-ini', 1, '--fpm-admin-value' ];
$options{'create-database-options'} = [ 'create-database', 0, '--opt' ];
# Each web-server effect must map to exactly its advertised options.
$options{'modify-web-logs'} = [ 'modify-web', 0, '--access-log', '--error-log', '--php-log' ];
$options{'modify-web-cert-paths'} = [ 'modify-web', 0, '--ssl-cert', '--ssl-key', '--ssl-ca', '--default-ssl-cert', '--default-ssl-key', '--default-ssl-ca', '--default-ssl-paths' ];
$options{'modify-web-directives'} = [ 'modify-web', 0, '--add-directive', '--remove-directive' ];
$options{'modify-web-ports'} = [ 'modify-web', 0, '--port', '--ssl-port', '--url-port', '--ssl-url-port' ];
$options{'modify-web-repair'} = [ 'modify-web', 1, '--fix-document-dir', '--fix-options', '--cleanup-mod-php' ];
$options{'modify-web-php-limits'} = [ 'modify-web', 1, '--php-children-no-check' ];
# Resource management and application overrides must not share authority.
$options{'enable-feature-associate'} = [ 'enable-feature', 0, '--associate' ];
$options{'disable-feature-disassociate'} = [ 'disable-feature', 0, '--disassociate' ];
$options{'delete-domain-only'} = [ 'delete-domain', 0, '--only' ];
$options{'install-script-unsupported'} = [ 'install-script', 1, '--unsupported' ];
$options{'install-script-log-only'} = [ 'install-script', 1, '--log-only' ];
$options{'install-script-global'} = [ 'install-script', 0 ];
$options{'delete-script-global'} = [ 'delete-script', 0 ];
$options{'start-stop-script-global'} = [ 'start-stop-script', 0 ];
# Listings need explicit secret-output grants; TLS keys may be shared.
$options{'list-certs-private-keys'} = [ 'list-certs', 0, '--key', '--newkey' ];
$options{'list-domains-secrets'} = [ 'list-domains', 1 ];
$options{'list-users-secrets'} = [ 'list-users', 1 ];
$options{'list-admins-secrets'} = [ 'list-admins', 1 ];
$options{'list-scripts-secrets'} = [ 'list-scripts', 1 ];
my $base = 'virtual-server:modify-domain';
my @catalog = list_api_access_commands();
is(scalar(grep { $_->{virtual} } @catalog), scalar(keys %options), 'all separate option grants are cataloged');
%access = (api_id => 'fixture', api_commands => $base, api_domains => 1);
prepare_api_access_command('modify-domain', [ '--desc', 'ordinary edit' ]);
ok(!api_access_system_command(), 'ordinary modification has no system authority');

# Each option needs its own grant, the base command, and its current context.
foreach my $name (sort keys %options) {
	my ($parent, $scoped, @flags) = @{$options{$name}};
	my $base = "virtual-server:$parent";
	my ($alias) = grep { $aliases{$_} eq $parent } keys %aliases;
	my $entry = get_api_access_command($name);
	is($entry->{parent}, $base, "$name is bound to the core command");
	is($entry->{scoped}, $scoped, "$name has the correct scope");
	ok(!$entry->{path}, "$name has no executable path");
	like($entry->{desc}, qr/Requires \Q$parent\E\./, "$name explains its dependency");
	foreach my $flag (@flags) {
		local $access{api_commands} = $base;
		eval { prepare_api_access_command($alias, [ $flag, 'value' ]) };
		like($@, qr/\Q$name\E/, "$flag denied without its extra grant");
		$access{api_commands} .= " virtual-server:$name";
		eval { prepare_api_access_command($alias, [ $flag, 'value' ]) };
		is($@, '', "$flag accepted with its own grant through an alias");
		ok(api_access_can_option($name), "$flag permission reaches the command");
		ok(!api_access_system_command(), 'an option grant does not elevate the base command');
		ok(!api_access_can_domain({ id => 2 }), 'extra permission does not widen domain access');
		foreach my $other (grep { $_ ne $name } keys %options) {
			ok(!api_access_can_option($other), 'other options remain blocked');
			}
		# Domain-only options support dry-run batches; root effects do not.
		my $output = '';
		{
			local *STDOUT;
			open(STDOUT, '>', \$output) or die $!;
			eval { run_api_access_batch([ '--domain', $domain{dom},
				'--test', '--command', $alias, $flag, 'value' ]) };
			}
		if ($entry->{scoped}) {
			# Domain-scoped options remain available in dry runs.
			is($@, '', "$flag can run in an authorized domain batch");
			like($output, qr/Would run \Q$parent\E/, 'dry run validates the base command');
			}
		else {
			# Reject server-wide effects before starting a batch.
			like($@, qr/server-wide option permissions/, "$flag cannot enter domain batches");
			}
		}
	# Runtime checks also cover file inputs and output without option flags.
	$access{api_commands} = $base;
	prepare_api_access_command($parent, [ ]);
	ok(!api_access_can_option($name), "$name is denied without its grant");
	$access{api_commands} .= " virtual-server:$name";
	ok(api_access_can_option($name), "$name is enabled in its own command");
	{
		local $api_access_domain_batch = 1;
		is(api_access_can_option($name) ? 1 : 0, $scoped,
			"$name respects domain batch boundaries at execution");
		}
	# Warnings must identify every grant with effects outside the target.
	ok($entry->{scoped} || $entry->{warning}, "$name warns about server-wide effects");
	# A permission entry cannot become an executable command itself.
	local $access{api_commands} = "$base virtual-server:$name";
	ok(!api_access_can_command($name), "$name cannot execute directly");
	eval { prepare_api_access_command($name, [ ]) };
	like($@, qr/not permitted/, "$name cannot become an executable batch command");
	{
		local $api_access_command;
		ok(!api_access_can_option($name), 'no command context denies the option');
		}
	{
		local $api_access_command = get_api_access_command(
		$parent eq 'create-domain' ? 'modify-domain' : 'create-domain');
		ok(!api_access_can_option($name), 'an unrelated command cannot borrow the option');
		}
	$access{api_commands} = "virtual-server:$name";
	ok(!api_access_can_option($name), 'option alone cannot authorize the base command');
	eval { prepare_api_access_command($parent, [ ]) };
	like($@, qr/not permitted/, 'base command still needs its own grant');
	$access{api_commands} = "$base virtual-server:$name";
	prepare_api_access_command($parent, [ ]);
	local $access{api_disabled} = 1;
	ok(!api_access_can_option($name), 'disabling the account revokes option grants');
	}
# Disk quota permission does not unlock other resource limits or provisioning.
$access{api_commands} = "$base virtual-server:modify-domain-quotas virtual-server:create-domain";
foreach my $flag ('--bandwidth', '--max-dbs', '--mailboxlimit') {
	eval { prepare_api_access_command('modify-domain', [ $flag, 'UNLIMITED' ]) };
	like($@, qr/limits from a plan/, "$flag remains controlled by plans");
	}
eval { prepare_api_access_command('create-domain', [ '--quota', 'UNLIMITED' ]) };
like($@, qr/limits from a plan/, 'modify quota grant cannot override creation limits');

# Edition filtering must remove extra grants together with their Pro parent.
{
	local $virtualmin_pro = 0;
	my %gpl = map { $_->{key} => $_ } grep { !$_->{pro} } @catalog;
	foreach my $entry (grep { $_->{virtual} } @catalog) {
		# Keys include providers; resolve the canonical parent name separately.
		(my $name = $entry->{parent}) =~ s/^.*://;
		my $parent = get_api_access_command($name);
		is($entry->{pro}, $parent->{pro}, 'extra grant inherits its parent edition');
		ok(!$gpl{$entry->{key}} || $gpl{$entry->{parent}},
			'GPL all-commands selection cannot include an orphaned extra grant');
		}
	local $access{api_commands} = 'virtual-server:create-domain virtual-server:create-domain-hooks';
	local $api_access_command = get_api_access_command('create-domain');
	ok(!api_access_can_option('create-domain-hooks'),
		'Pro option grant cannot authorize its parent after a downgrade');
}

# Replacing the base provider must never inherit its privileged option grants.
$provider = 'fixture-plugin';
$api_access_commands_loaded = 0;
@catalog = list_api_access_commands();
ok(!grep($_->{virtual}, @catalog), 'plugin replacements have no core option grants');
$access{api_commands} .= ' fixture-plugin:modify-domain';
prepare_api_access_command('modify-domain', [ ]);
ok(!api_access_can_option('modify-domain-quotas'), 'provider replacement cannot borrow the old grant');
eval { prepare_api_access_command('modify-domain', [ '--quota', 1 ]) };
like($@, qr/limits from a plan/, 'provider replacement retains the resource-limit guard');
done_testing();
