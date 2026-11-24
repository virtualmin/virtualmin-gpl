#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $feature = File::Spec->catfile($root, 'feature-postgres.pl');
my $loaded = do $feature;
die $@ if ($@);
die "Failed to load $feature: $!" if (!defined($loaded));

# Look up parents and the server version without loading Webmin.
my %doms = (
	1 => { 'id' => 1, 'pass' => "parent'pass" },
	2 => { 'id' => 2, 'pass' => 'domain-pass',
	       'postgres_pass' => "db'pass" },
	);
local *main::get_domain = sub { return $doms{$_[0]}; };
local *main::require_postgres = sub { };
local *main::get_dom_remote_postgres_version = sub { return '16.4'; };

# Top-level domains quote their own password for SQL unless asked not to.
my $top = $doms{1};
is(main::postgres_pass($top), "E'parent''pass'",
	'top-level password is quoted for SQL');
is(main::postgres_pass($top, 1), "parent'pass",
	'top-level password can be returned unquoted');
is(main::postgres_pass($doms{2}, 1), "db'pass",
	'separate PostgreSQL password is preferred');

# The Webmin module doubles every backslash before running SQL. An escape
# string turns each pair back into one, so the server gets the exact value.
foreach my $value ("a\\\\b", "a\\'b", "q'\\n") {
	my $sql = &postgres_quote($value);
	(my $sent = $sql) =~ s/\\/\\\\/g;
	my ($body) = $sent =~ /^E'(.*)'$/s;
	$body =~ s/''/'/g;
	$body =~ s/\\(.)/$1/gs;
	is($body, $value, "PostgreSQL receives $value exactly");
	}

# Sub-servers use the parent's login, with the same quoting choice.
my $sub = { 'id' => 3, 'parent' => 1, 'pass' => 'ignored' };
is(main::postgres_pass($sub), "E'parent''pass'",
	'sub-server password is quoted for SQL');
is(main::postgres_pass($sub, 1), "parent'pass",
	'sub-server password can be returned unquoted');
is(main::postgres_pass({ 'id' => 4, 'parent' => 2 }, 1), "db'pass",
	"sub-server uses the parent's separate PostgreSQL password");

# Create the login without a server, recording the password it is given.
my ($nopass, @sql);
local *main::get_template = sub {
	return { 'mysql_nopass' => $nopass, 'mysql_mkdb' => 0 };
	};
local *main::get_default_postgres_module = sub { return 'postgresql'; };
local *main::postgres_user_exists = sub { return 0; };
local *main::get_postgresql_user_flags = sub { return ''; };
local *main::execute_dom_psql = sub { push(@sql, $_[2]); };
local $main::first_print = local $main::second_print = sub { };

# Without syncing, later admin password changes must not change the login.
foreach my $mode (1, 2) {
	$nopass = $mode;
	@sql = ();
	my $new = { 'id' => 5, 'user' => 'fixture', 'pass' => "first'pass" };
	main::setup_postgres($new);
	like($sql[0], qr/with password E'first''pass'/,
		"mode $mode creates the login with the initial password");
	$new->{'pass'} = 'changed';
	is(main::postgres_pass($new, 1), "first'pass",
		"mode $mode keeps reporting the login's actual password");
	}

# Synced logins keep following the admin password.
$nopass = 0;
my $synced = { 'id' => 6, 'user' => 'fixture', 'pass' => 'first' };
main::setup_postgres($synced);
ok(!exists($synced->{'postgres_pass'}),
	'synced login stores no separate password');

done_testing();
