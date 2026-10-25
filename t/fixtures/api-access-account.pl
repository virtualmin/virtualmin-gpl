#!/usr/bin/perl
# api-access-account.pl(mode, fixture-file)
# Runs fixture operations using the driver's mode-0600 JSON file.
# Requires a disposable VM. API_TEST_WEBMIN_ROOT overrides /usr/share/webmin.
# Modes: setup, catalog, make-alias, module-root, inspect, block-policy,
# unblock-policy, edition-info, seed-pro-grants, make-pro-alias,
# theme-authentic, theme-gray, and cleanup.

use strict;
use warnings;
no warnings 'uninitialized';
use JSON::PP;
our (%access, $module_name, $module_config_directory, $module_root_directory,
     $virtualmin_pro);
# Allow the installed Webmin path to vary between disposable test VMs.
my $webmin_root = $ENV{'API_TEST_WEBMIN_ROOT'} || '/usr/share/webmin';
unshift(@INC, $webmin_root);
my ($mode, $file) = @ARGV;
# Load only the VM-local fixture file supplied by the test driver.
open(my $fh, '<', $file) or die "Cannot read fixture\n";
my $fixture = decode_json(do { local $/; <$fh> });
close($fh);
# Initialize the installed guest instance; this helper must not run locally.
$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
$main::no_acl_check = 1;
$0 = "$webmin_root/virtual-server/api-access-account.pl";
chdir("$webmin_root/virtual-server") or die $!;
require './virtual-server-lib.pl';
&require_acl();
my $policy_file = "$module_config_directory/$fixture->{user}.acl";
my $alias_file = "$fixture->{user}-acme-alias.pl";
my $pro_alias_file = "$fixture->{user}-create-alias.pl";

if ($mode eq 'setup') {
	# Use a temporary Webmin master credential to exercise the real admin UI.
	my $user = { name => $fixture->{admin},
		pass => &acl::encrypt_password($fixture->{admin_password}, '$6$fixture$'),
		modules => ['virtual-server'], nochange => 1 };
	(grep { $_->{name} eq $user->{name} } &acl::list_users()) && die 'Name clash';
	&acl::create_user($user);
	&save_module_acl({ noconfig => 0, domains => '*' }, $user->{name}, 'virtual-server', 1);
	&save_module_acl({ rpc => 0 }, $user->{name}, '', 1);
	# Distinct plans let the driver test allowed and forbidden selections.
	my $base = &get_default_plan();
	for my $name ('allowed', 'forbidden') {
		my $plan = { %$base, id => '', name => $fixture->{user}."-$name",
			featurelimits => 'unix dir webmin web mysql', quota => 131072,
			uquota => 65536, domslimit => 5, mailboxlimit => 3, dbslimit => 2 };
		&save_plan($plan);
		$fixture->{$name.'_plan'} = $plan->{id};
		}
	# Return generated plan IDs through the existing private fixture file.
	open($fh, '>', $file) or die $!;
	print $fh encode_json($fixture);
	close($fh);
	&reload_miniserv();
	}
elsif ($mode eq 'catalog') {
	# Return the current grant keys to check a saved all-commands selection.
	print encode_json([ map { $_->{'key'} } &list_api_access_commands() ]);
	}
elsif ($mode eq 'module-root') {
	# Return the configured module path for direct CLI tests.
	print "$module_root_directory\n";
	}
elsif ($mode eq 'edition-info') {
	# Report metadata independently of the current user's saved grants.
	print encode_json({ pro => $virtualmin_pro ? 1 : 0,
		commands => [ &list_api_access_commands() ] });
	}
elsif ($mode eq 'seed-pro-grants') {
	# Simulate a downgrade or hand-edited ACL on this fixture account only.
	my %a = &get_module_acl($fixture->{user}, $module_name);
	$a{'api_id'} || die "Missing fixture account";
	my @pro = map { $_->{'key'} } grep { $_->{'pro'} }
		&list_api_access_commands();
	$a{'api_commands'} = join(' ', &unique(split(/\s+/, $a{'api_commands'}), @pro));
	&save_module_acl(\%a, $fixture->{user}, $module_name, 1);
	}
elsif ($mode eq 'make-pro-alias') {
	# A packaged copy must resolve to the same edition rule as create-domain.
	!-e $pro_alias_file || die "Alias fixture already exists";
	my $source = &read_file_contents('create-domain.pl');
	$source || die "Missing alias source";
	# Keep the POD title and contents intact for alias detection.
	open(my $alias, '>', $pro_alias_file) or die $!;
	print $alias $source;
	close($alias) or die $!;
	chmod(0755, $pro_alias_file) or die $!;
	}
elsif ($mode =~ /^theme-(authentic|gray)$/) {
	# Change only the temporary administrator's theme, never the server default.
	my $theme = "$1-theme";
	-d "$webmin_root/$theme" || die "Missing test theme $theme";
	my ($admin) = grep { $_->{name} eq $fixture->{admin} } &acl::list_users();
	$admin || die "Missing fixture administrator";
	$admin->{theme} = $theme;
	&acl::modify_user($admin->{name}, $admin);
	}
elsif ($mode eq 'make-alias') {
	# Test packaged aliases with an exact copy, without changing installed names.
	!-e $alias_file || die "Alias fixture already exists";
	my $source = &read_file_contents('generate-acme-cert.pl');
	$source || die "Missing alias source";
	open(my $alias, '>', $alias_file) or die $!;
	print $alias $source;
	close($alias) or die $!;
	chmod(0755, $alias_file) or die $!;
	}
elsif ($mode eq 'inspect') {
	# Return only the fields asserted by the tests, never saved passwords.
	# A directory at the ACL path represents the injected write failure.
	my %a = -d $policy_file ? () : &get_module_acl($fixture->{user}, 'virtual-server');
	my %g = &get_module_acl($fixture->{user}, '');
	my $d = &get_domain_by('dom', $fixture->{domain});
	my $outside = &get_domain_by('dom', $fixture->{outside});
	my $clone = &get_domain_by('dom', $fixture->{clone});
	my ($account) = grep { $_->{name} eq $fixture->{user} } &acl::list_users();
	# Include saved ownership and limits for the driver's assertions.
	print encode_json({ api_id => $a{api_id}, noconfig => $a{noconfig},
		account_exists => $account ? 1 : 0,
		description => $account ? $account->{real} : undef,
		other_descriptions => scalar(grep {
			$_->{name} ne $fixture->{user} && $_->{real} =~ /\S/
			} &list_api_access_users()),
		account_locked => $account && $account->{pass} eq '!' ? 1 : 0,
		api_commands => $a{api_commands}, api_domains => $a{api_domains},
		api_disabled => $a{api_disabled},
		rpc => $g{rpc}, api_only => $g{api_only},
		outside_id => $outside ? $outside->{id} : undef,
		clone_owner => $clone ? $clone->{api_owner} : undef,
		domain => $d ? { map { $_ => $d->{$_} }
			qw(id dom user api_owner plan template quota uquota) } : undef,
		unix_user => scalar(getpwnam($fixture->{user})) });
	}
elsif ($mode eq 'block-policy') {
	# Force a real file-backed ACL write failure for this new fixture only.
	my ($account) = grep { $_->{name} eq $fixture->{user} } &acl::list_users();
	!$account && !-e $policy_file || die "Fixture already exists";
	mkdir($policy_file) || die "Cannot block fixture policy: $!";
	}
elsif ($mode eq 'unblock-policy') {
	# Remove the fault and any locked account left by the failed creation.
	rmdir($policy_file) || die "Cannot unblock fixture policy: $!";
	my ($account) = grep { $_->{name} eq $fixture->{user} } &acl::list_users();
	# Creation may have failed before a login was saved.
	&acl::delete_user($fixture->{user}) if ($account);
	&reload_miniserv();
	}
elsif ($mode eq 'cleanup') {
	# The driver handles domain deletion through the administrator API.
	# Remove test aliases only if their setup steps completed.
	unlink($alias_file) or die $! if (-e $alias_file);
	unlink($pro_alias_file) or die $! if (-e $pro_alias_file);
	# Remove the directory left by an interrupted write-failure test.
	rmdir($policy_file) || die "Cannot remove fixture fault: $!" if (-d $policy_file);
	# Delete only fixture logins; leave other accounts unchanged.
	my %names = map { $_->{name} => 1 } &acl::list_users();
	for my $name ($fixture->{user}, $fixture->{admin}) {
		# Setup may have failed before creating both accounts.
		&acl::delete_user($name) if ($names{$name});
		}
	# Check plan names as well as IDs before removing fixture data.
	for my $kind ('allowed', 'forbidden') {
		my $p = &get_plan($fixture->{$kind.'_plan'});
		&delete_plan($p) if ($p && $p->{name} eq $fixture->{user}."-$kind");
		}
	&reload_miniserv();
	# Domain cleanup runs first; report anything left instead of hiding it.
	my @left = grep { &get_domain_by('dom', $_) }
		($fixture->{domain}, $fixture->{outside}, $fixture->{clone},
		 $fixture->{user}.'-blocked.example.test');
	die "Fixture domains remain: ".join(', ', @left)."\n" if (@left);
	}
else {
	# Reject unknown operations instead of leaving ambiguous fixture state.
	die "Unknown fixture operation\n";
	}
