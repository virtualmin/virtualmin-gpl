#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(abs_path);
use version;

my $root = abs_path(File::Spec->catdir(dirname(__FILE__), '..'));
my $feature = File::Spec->catfile($root, 'feature-mysql.pl');
my $loaded = do $feature;
die $@ if ($@);
die "Failed to load $feature: $!" if (!defined($loaded));

# Supply server metadata without loading Webmin or contacting a database.
my ($server_version, $variant, $plugin, $query_error);
my (@queries, @commands);
my $dom = { 'id' => 1 };
my $pass = "fixture'password";
my $pass_sql = "password('fixture''password')";
local $mysql::master_db = 'mysql';
local $mysql::password_func = 'password';
local %mysql::config = ( 'mysql' => 'mysql' );
local *main::require_mysql = sub { };
local *main::require_dom_mysql = sub { return 'mysql'; };
local *main::get_dom_remote_mysql_version = sub {
	return ($server_version, $variant);
	};
local *main::compare_versions = sub {
	return version->parse('v'.$_[0]) <=> version->parse('v'.$_[1]);
	};
local *main::unique = sub {
	my %seen;
	return grep { !$seen{$_}++ } @_;
	};
local *main::to_ipaddress = sub { return $_[0]; };
local *main::error = sub { die $_[0]; };

# Record writes while returning two distinct account hosts and their plugin.
local *main::execute_dom_sql = sub {
	my ($d, $db, $sql) = @_;
	return { 'data' => [ ['127.0.0.1'], ['localhost'], ['127.0.0.1'] ] }
		if ($sql =~ /^select host/);
	return { 'data' => [ [$plugin] ] } if ($sql =~ /^select plugin/);
	push(@queries, $sql);
	die "$query_error\n" if ($query_error && $sql !~ /^flush privileges/);
	return { 'data' => [] };
	};

# Capture direct reset commands without executing a local database client.
local *main::backquote_command = sub {
	push(@commands, $_[0]);
	$? = 0;
	return '';
	};

# Older MariaDB uses SET PASSWORD; retain modern plugin-specific SQL.
foreach my $case (
	[ '10.1.48', 'mariadb', 'mysql_native_password', "set password for %s = $pass_sql" ],
	[ '10.2.44', 'mariadb', 'mysql_native_password', "set password for %s = $pass_sql" ],
	[ '10.3.39', 'mariadb', 'mysql_native_password', "set password for %s = $pass_sql" ],
	[ '10.4.0', 'mariadb', 'mysql_native_password', "alter user %s identified via mysql_native_password using $pass_sql" ],
	[ '10.11.6', 'mariadb', 'mysql_native_password', "alter user %s identified via mysql_native_password using $pass_sql" ],
	[ '5.7.44', 'mysql', 'mysql_native_password', "alter user %s identified with mysql_native_password by 'fixture''password'" ],
	[ '8.0.36', 'mysql', 'caching_sha2_password', "alter user %s identified with caching_sha2_password by 'fixture''password'" ],
	) {
	my $format;
	($server_version, $variant, $plugin, $format) = @$case;
	@queries = ();
	main::execute_password_change_sql($dom, 'fixture', undef, $pass);
	is_deeply(\@queries, [ 'flush privileges',
		map { sprintf($format, "'fixture'\@'$_'") }
		    ('127.0.0.1', 'localhost') ],
		"$variant $server_version changes each host once and escapes the password");

	# The direct reset path must use the same version-specific statement.
	@commands = ();
	my $error = main::execute_password_change_sql(
		$dom, 'fixture', undef, $pass, 1);
	ok(!defined($error), "$variant $server_version direct reset succeeds");
	is_deeply(\@commands, [ 'mysql -D mysql -e '.
		quotemeta('flush privileges; '.
			sprintf($format, "'fixture'\@'localhost'")).
		' 2>&1 </dev/null' ],
		"$variant $server_version direct reset uses compatible SQL");
	}

# Restores can supply a hash without a plaintext password on older MariaDB.
($server_version, $variant, $plugin) =
	('10.3.39', 'mariadb', 'mysql_native_password');
my $hash_sql = "'*".('A' x 40)."'";
@queries = ();
main::execute_password_change_sql($dom, 'fixture', $hash_sql);
is_deeply(\@queries, [ 'flush privileges',
	map { "set password for 'fixture'\@'$_' = $hash_sql" }
	    ('127.0.0.1', 'localhost') ],
	'MariaDB 10.3 preserves a supplied password hash');

# A rejected password update must still propagate the database error.
$query_error = 'fixture database error';
eval { main::execute_password_change_sql($dom, 'fixture', undef, $pass); };
like($@, qr/fixture database error/, 'password update failures reach the caller');

# Login checks must use the app's login in the domain's own module, which is a
# clone in its own package for a remote server. The module connects through
# DBI with its login variables, or runs the mysql command with login options
# and a password built when it loaded. The admin login accepts any password.
my @logins;
local $ENV{'MYSQL_PWD'} = 'admin-pass';
local *main::foreign_call = sub {
	my ($mod, $func, @args) = @_;
	(my $pkg = $mod) =~ s/[^A-Za-z0-9]/_/g;
	no strict 'refs';
	return &{$pkg."::".$func}(@args);
	};
foreach my $mod ('mysql', 'mysql-remote') {
	(my $pkg = $mod) =~ s/[^A-Za-z0-9]/_/g;
	no strict 'refs';
	${$pkg."::mysql_login"} = 'root';
	${$pkg."::mysql_pass"} = 'admin-pass';
	${$pkg."::authstr"} = '-u root';
	${$pkg."::make_authstr_pass"} = 'admin-pass';
	*{$pkg."::make_authstr"} = sub {
		${$pkg."::make_authstr_pass"} = $_[1];
		$ENV{'MYSQL_PWD'} = $_[1];
		return "-u $_[0]";
		};
	local *main::require_dom_mysql = sub { return $mod; };
	foreach my $path ('DBI', 'mysql command') {
		local *main::execute_dom_sql = sub {
			my ($login, $pass) = $path eq 'DBI' ?
			    (${$pkg."::mysql_login"}, ${$pkg."::mysql_pass"}) :
			    (${$pkg."::authstr"} =~ /^-u (\S+)/,
			     $ENV{'MYSQL_PWD'});
			push(@logins, $login);
			$pass eq 'app-pass' || $login eq 'root' ||
				die "Access denied\n";
			return { 'data' => [] };
			};
		ok(main::check_mysql_login($dom, 'db', 'app', 'wrong'),
		   "a wrong password fails the $path check on module $mod");
		is(main::check_mysql_login($dom, 'db', 'app', 'app-pass'),
		   undef,
		   "the right password passes the $path check on module $mod");
		}
	is_deeply([ ${$pkg."::mysql_login"}, ${$pkg."::authstr"},
		    ${$pkg."::make_authstr_pass"} ],
		  [ 'root', '-u root', 'admin-pass' ],
		  "module $mod gets its own login back");
	}
is($ENV{'MYSQL_PWD'}, 'admin-pass', 'the password variable is restored');
is_deeply(\@logins, [ ('app') x 8 ], 'every check logs in as the app user');

done_testing();
