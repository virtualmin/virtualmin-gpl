#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);

my $root = "$FindBin::Bin/..";

# Each CLI case gets a fresh process, with all host operations replaced below.
if (@ARGV && $ARGV[0] eq '--child') {
	Test::More->builder()->no_ending(1);
	shift(@ARGV);
	my ($feature, $result, $missing, $tmp) = splice(@ARGV, 0, 4);
	virtual_server::setup_fixture($feature, $result, $missing, $tmp);
	load_functions();
	@ARGV = ('--domain', 'source.invalid', '--newdomain', 'target.invalid',
		'--newuser', 'target');
	die 'Cannot find clone-domain.pl' unless -f "$root/clone-domain.pl";
	do "$root/clone-domain.pl";
	die $@ if $@;
	exit(0);
	}

my $tmp = tempdir('clone-domain-exit-XXXXXX', TMPDIR => 1, CLEANUP => 1);

# Exercise the real Apache early returns, through the real CLI entry point.
foreach my $feature (qw(web ssl)) {
	foreach my $missing (qw(source target)) {
		subtest "$feature clone with missing $missing" => sub {
			my ($status, $output) = run_cli($feature, 'zero', $missing);
			is($status, 1, 'CLI exits with failure');
			my $label = $missing eq 'source' ? 'source' : 'destination';
			like($output, qr/\Q$label Apache configuration not found\E/,
				'reaches the real missing-vhost error');
			check_completion($output);
			};
		}
	}

# A later successful feature must not overwrite an earlier failure. Legacy
# handlers may return undef or an empty string after completing successfully.
foreach my $feature (qw(core plugin)) {
	foreach my $result (qw(zero exception success undef empty)) {
		subtest "$feature handler returns $result" => sub {
			my ($status, $output) = run_cli($feature, $result, '');
			my $failed = $result eq 'zero' || $result eq 'exception';
			is($status, $failed ? 1 : 0, 'CLI reports the feature result');
			like($output, qr/Controlled clone exception/,
				'keeps the exception diagnostic') if $result eq 'exception';
			check_completion($output);
			};
		}
	}

# Database cloning must preserve failures while allowing empty and renamed DBs.
foreach my $feature (qw(postgres mysql)) {
	foreach my $result (qw(no_db success prefix clash create backup restore empty_backup empty_restore
			       mixed_create mixed_backup mixed_restore),
			       $feature eq 'mysql' ? qw(hosts no_db_hosts) : ()) {
		subtest "$feature clone with $result" => sub {
			my ($status, $output) = run_cli($feature, $result, '');
			my $success = $result eq 'no_db' || $result eq 'success' ||
				$feature eq 'mysql' && $result eq 'prefix';
			is($status, $success ? 0 : 1, 'CLI reports the database clone result');
			my %errors = (prefix => qr/could not work out a new name/,
				clash => qr/a database named target already exists/,
				create => qr/creation of database target failed/,
				backup => qr/Controlled backup failure/,
				restore => qr/Controlled restore failure/,
				hosts => qr/Controlled allowed-hosts failure/,
				no_db_hosts => qr/Controlled allowed-hosts failure/,
				empty_backup => qr/backup of source failed/,
				empty_restore => qr/restore into target failed/);
			(my $failure = $result) =~ s/^mixed_//;
			like($output, $errors{$failure}, 'reports the expected database failure')
				unless $success;
			like($output, qr/created 0 databases/, 'empty database list is exercised')
				if $result =~ /^no_db/;
			like($output, qr/Restored target_extra/, 'copies the later database')
				if $result =~ /^mixed_/;
			like($output, qr/Restored target\n/, 'copies the primary database')
				if $result eq 'success' || $feature eq 'mysql' && $result eq 'prefix';
			like($output, qr/Allowed hosts processed/, 'also copies allowed hosts')
				if $feature eq 'mysql';
			check_completion($output);
			};
		}
}

# Applying configuration and running the after-clone command affect CLI status.
foreach my $result (qw(success no_actions zero exception count_zero
		       hook_failure hook_empty combined_failure)) {
	subtest "clone completion with $result" => sub {
		my ($status, $output) = run_cli('post', $result, '');
		my $success = $result =~ /^(success|no_actions|count_zero)$/;
		is($status, $success ? 0 : 1, 'CLI reports completion failures');
		like($output, qr/Clone saved\nDomain unlocked/, 'saves and unlocks the clone');
		like($output, qr/After-clone command ran/, 'runs the after-clone command');
		like($output, qr/After-clone command ran\n.*?Clone environment reset\n/s, 'resets the clone environment after the hook');
		like($output, qr/Post actions ran/, 'runs later actions despite a failure')
			unless $result eq 'no_actions';
		like($output, qr/Controlled post-action exception/, 'prints the exception')
			if $result eq 'exception';
		like($output, qr/Post-creation command failed/, 'prints the hook failure')
			if $result =~ /^hook_/ || $result eq 'combined_failure';
		};
	}

# Only list callers request the plugin's return value. Existing scalar callers
# still receive the exception status, including when a plugin returns zero.
load_functions();
foreach my $result (qw(zero exception success undef empty)) {
	subtest "plugin wrapper compatibility for $result" => sub {
		local $virtual_server::result = $result;
		local $virtual_server::second_print = sub { };
		my $status = virtual_server::try_plugin_call('fixture', 'feature_clone');
		is($status, $result eq 'exception' ? 0 : 1,
			'scalar callers retain exception-only status');
		is($virtual_server::call_context, 'void',
			'existing callers preserve the plugin calling context');
		my @rv = virtual_server::try_plugin_call('fixture', 'feature_clone');
		my $value = $result eq 'zero' ? 0 : $result eq 'success' ? 1 :
			$result eq 'empty' ? '' : undef;
		is_deeply(\@rv, $result eq 'exception' ? [ 0 ] : [ 1, $value ],
			'list callers receive exception status and actual result');
		is($virtual_server::call_context, 'scalar',
			'return value is captured in scalar context');
		};
	}
done_testing();

# Extract complete functions without loading Webmin or other module libraries.
sub load_functions
{
foreach my $spec (
	[ 'virtual-server-lib-funcs.pl', qw(clone_virtual_server try_function try_plugin_call) ],
	[ 'feature-web.pl', qw(clone_web obtain_lock_web release_lock_web) ],
	[ 'feature-ssl.pl', 'clone_ssl' ],
	[ 'feature-postgres.pl', 'clone_postgres' ],
	[ 'feature-mysql.pl', 'clone_mysql' ]) {
	my ($file, @names) = @$spec;
	push(@names, qw(run_post_actions made_changes))
		if $file eq 'virtual-server-lib-funcs.pl' && ($virtual_server::feature || '') eq 'post';
	open(my $fh, '<', "$root/$file") or die "$file: $!";
	my $source = do { local $/; <$fh> };
	close($fh);
	foreach my $name (@names) {
		my ($function) = $source =~ /(^sub \Q$name\E\n\{.*?^\})/ms;
		die "Cannot find $name in $file" unless $function;
		eval "package virtual_server; no strict; no warnings; $function";
		die $@ if $@;
		}
	}
}

# Capture the actual process exit status, without functional-test text filters.
sub run_cli
{
my ($feature, $result, $missing) = @_;
open(my $fh, '-|', $^X, "$FindBin::Bin/clone-domain-exit.t", '--child',
	$feature, $result, $missing, $tmp) or die "Cannot run fixture: $!";
my $output = do { local $/; <$fh> };
close($fh);
return ($? & 127 ? 128 + ($? & 127) : $? >> 8, $output);
}

# Failure reporting must still allow later features, saving, and lock release.
sub check_completion
{
my ($output) = @_;
like($output, qr/Later core feature ran/, 'runs remaining core features');
like($output, qr/Later plugin ran/, 'runs remaining plugins');
like($output, qr/Clone saved\nDomain unlocked\nPost actions ran/,
	'saves the clone, releases its lock, and applies pending changes');
}

package virtual_server;
no strict;
no warnings;

# In-memory fixture state prevents account, file, and service changes.
sub setup_fixture
{
($feature, $result, $missing, $tmp) = @_;
$module_name = 'virtual-server';
$script_log_directory = "$tmp/scripts";
@features = ($feature =~ /^(web|ssl|postgres|mysql)$/ ? $feature : 'probe', 'after');
@plugins = ($feature eq 'plugin' ? ('fixture') : (), 'later');
%config = (web => 1, post_command => $feature eq 'post' ? 'fixture' : '');
$source = { id => 'source-id', dom => 'source.invalid', user => 'source',
	home => "$tmp/source", template => 0, web_port => 80, web_sslport => 443,
	db => 'source', prefix => 'source',
	map { $_ => 1 } (@features, @plugins) };
open(my $lang, '<', "$root/lang/en") or die $!;
while (<$lang>) {
	chomp;
	my ($key, $value) = split(/=/, $_, 2);
	$text{$key} = $value if defined($value);
	}
close($lang);
}

# Keep argument parsing and clone orchestration real, replacing host helpers.
sub set_all_text_print {
	$first_print = $second_print = sub { print "@_\n"; };
	$indent_print = $outdent_print = sub { };
}
sub text {
	my ($key, @values) = @_;
	my $message = $text{$key} || $key;
	$message =~ s/\$(\d+)/$values[$1-1]/ge;
	return $message;
}
sub parse_domain_name { $_[0] }
sub valid_domain_name { undef }
sub master_admin { 1 }
sub get_remote_api_domain { $source }
sub get_domain_by { undef }
sub get_template { {} }
sub domain_id { 'target-id' }
sub get_system_hostname { 'fixture.invalid' }
sub server_home_directory { "$tmp/target" }
sub compute_prefix { 'target' }
sub database_name { $_[0]->{'prefix'} }
sub virtual_server_depends { undef }
sub virtual_server_clashes { undef }
sub create_virtual_server { undef }
sub set_domain_envs { }
sub reset_domain_envs {
	print "Clone environment reset\n" if $feature eq 'post';
}
sub making_changes { undef }
sub made_changes { undef }
sub lock_domain { }
sub save_domain { print "Clone saved\n"; }
sub unlock_domain { print "Domain unlocked\n"; }
sub refresh_webmin_user { }
sub run_post_actions { print "Post actions ran\n"; }
sub virtualmin_api_log { }
sub plugin_defined { 1 }
sub indexof {
	my ($item, @items) = @_;
	foreach my $i (0 .. $#items) {
		return $i if $items[$i] eq $item;
		}
	return -1;
}

# Only virtual-host lookup is missing; the Apache error branches are unmodified.
sub get_domain_php_mode { 'none' }
sub obtain_lock_anything { }
sub release_lock_anything { }
sub get_website_file { "$tmp/apache/$_[0]->{'dom'}.conf" }
sub require_apache { }
sub lock_file { }
sub unlock_file { }
sub get_apache_virtual {
	my ($domain) = @_;
	return () if $domain eq "$missing.invalid";
	my $members = [];
	my $virt = { members => $members, file => "$tmp/apache/$domain.conf" };
	return ($virt, $members, [ $virt ]);
}
sub apache::find_httpd_conf { "$virtual_server::tmp/apache/httpd.conf" }
sub apache::flush_config_cache { }

# Keep both database clone handlers real, replacing database and file operations.
sub domain_databases {
	my ($d) = @_;
	return @created_dbs if $d->{'dom'} eq 'target.invalid';
	return () if $result =~ /^no_db/;
	return ({ name => 'unmatched' }) if $result eq 'prefix';
	return ({ name => 'source' },
		$result =~ /^mixed_/ ? ({ name => 'source_extra' }) : ());
}
sub fix_database_name { $_[0] }
sub check_postgres_database_clash { $result eq 'clash' }
sub push_all_print { }
sub set_all_null_print { }
sub pop_all_print { }
sub get_postgres_creation_opts { {} }
sub create_fixture_database {
	return 0 if $result =~ /^(mixed_)?create$/ && $_[1] eq 'target';
	push(@created_dbs, { name => $_[1] });
	return 1;
}
sub create_postgres_database { create_fixture_database(@_) }
sub create_mysql_database { create_fixture_database(@_) }
sub check_mysql_database_clash { $result eq 'clash' }
sub get_mysql_creation_opts { {} }
sub require_mysql { }
sub require_dom_mysql { 'mysql' }
sub foreign_defined { 0 }
sub mysql_single_transaction { 1 }
sub get_mysql_allowed_hosts { ('localhost') }
sub save_mysql_allowed_hosts {
	print "Allowed hosts processed\n";
	return $result =~ /hosts$/ ? 'Controlled allowed-hosts failure' : undef;
}
sub execute_dom_sql_file {
	my $err = foreign_call('mysql', 'restore_database', $_[1]);
	return defined($err) ? (1, $err) : (0, '');
}
sub require_postgres { }
sub require_dom_postgres { 'postgresql' }
sub transname { "$tmp/unused-dump" }
sub get_dom_postgres_creds { (0, '') }
sub unlink_file { }
sub foreign_call {
	my ($mod, $func, $db) = @_;
	return '' if $func eq 'backup_database' && $result eq 'empty_backup';
	return '' if $func eq 'restore_database' && $result eq 'empty_restore';
	return 'Controlled backup failure' if $func eq 'backup_database' &&
		$result =~ /^(mixed_)?backup$/ && $db eq 'source';
	return 'Controlled restore failure' if $func eq 'restore_database' &&
		$result =~ /^(mixed_)?restore$/ && $db eq 'target';
	print "Restored $db\n" if $func eq 'restore_database';
	return undef;
}

# Probe return values independently of printing and other side effects.
sub clone_probe { return $feature =~ /^(plugin|post)$/ ? 1 : probe_result(); }
sub clone_after {
	print "Later core feature ran\n";
	if ($feature eq 'post' && $result ne 'no_actions') {
		@main::post_actions = ([ $result eq 'count_zero' ?
			\&post_count : \&restart_apache ], [ \&post_later ]);
		}
	return 1;
}
sub restart_apache {
	die "Controlled post-action exception\n" if $result eq 'exception';
	return $result =~ /^(zero|combined_failure)$/ ? 0 : 1;
}
sub post_count { 0 }
sub post_later { print "Post actions ran\n"; }
sub clean_changes_environment { }
sub reset_changes_environment { }
sub backquote_logged {
	print "After-clone command ran\n";
	$? = $result =~ /^hook_/ || $result eq 'combined_failure' ? 256 : 0;
	return $result eq 'hook_empty' ? '' : $? ? 'Controlled hook failure' : '';
}
sub plugin_call {
	my ($plugin, $function) = @_;
	return 'Fixture plugin' if $function eq 'feature_name';
	$call_context = !defined(wantarray) ? 'void' : wantarray ? 'list' : 'scalar';
	if ($plugin eq 'later') {
		print "Later plugin ran\n";
		return 1;
		}
	return probe_result();
}
sub probe_result {
	die "Controlled clone exception\n" if $result eq 'exception';
	return 0 if $result eq 'zero';
	return undef if $result eq 'undef';
	return '' if $result eq 'empty';
	return 1;
}
