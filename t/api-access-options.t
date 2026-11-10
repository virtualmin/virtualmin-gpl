#!/usr/bin/perl
# Test separate API option grants with the real catalog and batch dispatcher.
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
our (%access, %text, $module_name, $virtualmin_pro, $api_access_command,
     $api_access_commands_loaded, @api_access_commands);
$module_name = 'virtual-server';
$virtualmin_pro = 1;
do "$FindBin::Bin/../security-lib.pl" or die $@ || $!;
do "$FindBin::Bin/../commands-lib.pl" or die $@ || $!;
do "$FindBin::Bin/../api-access-lib.pl" or die $@ || $!;

# Provide executable fixture commands without initializing the host's Webmin.
my $dir = tempdir(CLEANUP => 1);
my $provider = $module_name;
my %aliases = ( 'modify-alias' => 'modify-domain',
	'rename-alias' => 'rename-domain', 'user-alias' => 'create-user' );
foreach my $name (qw(modify-domain rename-domain create-user create-domain list-domains)) {
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
			qw(modify-domain modify-alias rename-domain rename-alias
			    create-user user-alias create-domain list-domains);
		};
	}
# plugin_defined(provider, function): no fixture plugin declares domain access.
sub plugin_defined { return 0; }
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
my $base = 'virtual-server:modify-domain';
my @catalog = list_api_access_commands();
is(scalar(grep { $_->{virtual} } @catalog), 9, 'nine separate option grants');
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
			is($@, '', "$flag can run in an authorized domain batch");
			like($output, qr/Would run \Q$parent\E/, 'dry run validates the base command');
			}
		else {
			like($@, qr/server-wide option permissions/, "$flag cannot enter domain batches");
			}
		}
	local $access{api_commands} = "$base virtual-server:$name";
	ok(!api_access_can_command($name), "$name cannot execute directly");
	eval { prepare_api_access_command($name, [ ]) };
	like($@, qr/not permitted/, "$name cannot become an executable batch command");
	{
		local $api_access_command;
		ok(!api_access_can_option($name), 'no command context denies the option');
		}
	{
		local $api_access_command = get_api_access_command('create-domain');
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
