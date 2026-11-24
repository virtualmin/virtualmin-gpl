#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);

my $root = "$FindBin::Bin/..";
my ($webmin) = grep { defined($_) && -r "$_/web-lib-funcs.pl" &&
		     -r "$_/WebminCore.pm" }
	$ENV{'WEBMIN_ROOT'}, "$root/..", "$root/../webmin";
plan(skip_all => 'Set WEBMIN_ROOT to the Webmin source tree') if (!$webmin);
{
	# Virtualmin imports the pattern generator through WebminCore.
	local @INC = ($webmin, @INC);
	require WebminCore;
	WebminCore->import();
	}
require "$root/scripts/roundcube.pl";

# Run the actual installer callback with real files and the real Webmin RNG.
# Database, archive extraction, PHP execution and web-server changes are stubbed.
my $tmp = tempdir(CLEANUP => 1);
my $domain = { dom => 'roundcube.invalid', home => $tmp };
my ($serial, $updates, $generations, $writes) = (0, 0, 0, 0);
my %lines;
my $generator = \&main::substitute_pattern;
no warnings qw(once redefine);
local *main::mysql_user = sub { 'roundcube' };
local *main::mysql_pass = sub { 'fixture-password' };
local *main::get_database_host = sub { 'localhost' };
local *main::check_script_db_connection = sub { undef };
local *main::transname = sub { "$tmp/extract" };
local *main::extract_script_archive = sub { undef };
local *main::get_domain_spam_delivery = sub { (0, '') };
local *main::php_quotemeta = sub { $_[0] };
local *main::require_mysql = sub { };
local *main::execute_dom_sql_file = sub { (0, '') };
local *main::substitute_pattern = sub {
	$generations++;
	is(scalar(@_), 1, 'installer uses the existing pattern API');
	return &$generator(@_);
	};
local *main::compare_versions = sub { $_[0] =~ /^1\.7\./ ? 1 : -1 };
local *main::list_redirects = sub { () };
local *main::domain_has_website = sub { 'web' };
local *main::create_redirect = sub { undef };
local *main::script_path_url = sub { 'https://roundcube.invalid/roundcube' };
local *main::get_php_cli_command = sub { '/usr/bin/php' };
local *main::run_as_domain_user = sub { $updates++; return ('', 0); };
local *main::copy_source_dest_as_domain_user = sub { copy($_[1], $_[2]) || die $! };
local *main::read_file_lines_as_domain_user = sub {
	my (undef, $file) = @_;
	my @content = split(/\n/, read_config($file));
	return $lines{$file} = \@content;
	};
local *main::flush_file_lines_as_domain_user = sub {
	my (undef, $file) = @_;
	$writes++;
	write_config($file, join("\n", @{$lines{$file}})."\n");
	};

# These settings are taken from config/config.inc.php.sample in Roundcube
# 1.7.6 and 1.6.21. Unrelated comments and settings are omitted.
my $sample = <<'PHP';
<?php
$config = [];
$config['db_dsnw'] = 'mysql://roundcube:pass@localhost/roundcubemail';
$config['des_key'] = 'rcmail-!24ByteDESkey*Str';
PHP

subtest 'Fresh installs and repeat upgrades' => sub {
	my @keys;
	for my $version ('1.6.21', '1.7.6') {
		my ($opts, $file) = fixture($sample);
		my ($ok, $msg) = install($version, $opts);
		is($ok, 1, "$version installation succeeds") || diag($msg);
		my $saved = read_config($file);
		my ($key) = $saved =~ /\['des_key'\] = '([^']+)';/;
		like($key, qr/\A[A-Za-z0-9]{24}\z/, 'saved key has the required format');
		push(@keys, $key);
		my $before_writes = $writes;
		($ok, $msg) = install($version, $opts, 1);
		is($ok, 1, 'upgrade succeeds');
		is(read_config($file), $saved, 'upgrade preserves the generated key');
		is($writes, $before_writes, 'custom configuration is not rewritten');
		unlike($msg, qr/must sign in again/, 'no rotation notice for a preserved key');
		}
	isnt($keys[0], $keys[1], 'fresh installations receive different keys');
	};

subtest 'Upgrades replace only literal sample keys' => sub {
	for my $case (
		[ $sample, 0 ],
		[ qq{<?php\n  \$config [ "des_key" ] = "rcmail-!24ByteDESkey*Str"; // keep\n}, 0 ],
		[ $sample =~ s/\$config/\$rcmail_config/gr, 1 ],
		[ $sample.q{$config['des_key'] = 'rcmail-!24ByteDESkey*Str';}."\n", 0 ],
		) {
		my ($opts, $file) = fixture($case->[0], 1, $case->[1]);
		my $before = $generations;
		my ($ok, $msg) = install('1.7.6', $opts, 1);
		is($ok, 1, 'sample-key upgrade succeeds') || diag($msg);
		is($generations, $before + 1, 'one key is generated for the installation');
		my $saved = read_config($file);
		my @keys = $saved =~ /['"]des_key['"]\s*\]\s*=\s*['"]([A-Za-z0-9]{24})['"]/g;
		ok(@keys, 'upgrade writes a 24-character key');
		my $expected = $case->[0];
		$expected =~ s/rcmail-!24ByteDESkey\*Str/$keys[0]/g;
		is($saved, $expected, 'all other config bytes are preserved');
		like($msg, qr/must sign in again/, 'upgrade explains session invalidation');
		install('1.7.6', $opts, 1);
		is(read_config($file), $saved, 'a later upgrade does not rotate it again');
		}
	for my $key ("'custom-owner-key-1234567'", 'getenv("ROUNDCUBE_KEY")',
		     "'rcmail-!24ByteDESkey*Str-custom'") {
		my $config = $sample;
		$config =~ s/'rcmail-!24ByteDESkey\*Str'/$key/;
		my ($opts, $file) = fixture($config, 1);
		install('1.7.6', $opts, 1);
		is(read_config($file), $config, 'custom key or expression is preserved');
		}
	};

subtest 'Older Webmin without the secure randomness API' => sub {
	local *main::secure_random_bytes;
	local *WebminCore::secure_random_bytes;
	for my $upgrade (0, 1) {
		my ($opts, $file) = fixture($sample, $upgrade);
		my ($ok, $msg) = install('1.7.6', $opts, $upgrade);
		is($ok, 1, 'installation or upgrade succeeds without the new API') || diag($msg);
		like(read_config($file), qr/\['des_key'\] = '[A-Za-z0-9]{24}';/,
			'the sample key is replaced using the existing generator');
		}
	};

subtest 'Updater failures stop the upgrade' => sub {
	for my $output ("Update failed: <database>& error\n", '') {
		my ($opts, $file) = fixture($sample, 1);
		make_path("$opts->{'dir'}/bin");
		write_config("$opts->{'dir'}/bin/update.sh",
			'print STDERR q{'.$output.'}; exit 7;');
		local *main::get_php_cli_command = sub { $^X };
		local *main::run_as_domain_user = sub {
			# Execute a real failing command using the helper's list contract.
			my (undef, $cmd) = @_;
			my $out = qx{$cmd};
			my $status = $?;
			$? = 0;
			return ($out, $status);
			};
		my $aliases = 0;
		local *main::create_redirect = sub { $aliases++; return undef; };
		my $before = $writes;
		my ($ok, $msg) = install('1.7.6', $opts, 1);
		is($ok, 0, 'failed updater returns failure to the CGI and CLI');
		like($msg, qr/Failed to run RoundCube update script/,
			'failure identifies the updater even without output');
		if (length($output)) {
			like($msg, qr/&lt;database&gt;&amp; error/,
				'stderr is captured and escaped for display');
			}
		unlike($msg, qr/upgrade complete/, 'no success message is returned');
		is(read_config($file), $sample, 'failure leaves the key unchanged');
		is($writes, $before, 'failure does not write the configuration');
		is($aliases, 0, 'failure does not change website aliases');
		}
	};

done_testing();

# fixture(config, [upgrade], [legacy])
# Create sample and optional active configuration files for an installation.
sub fixture
{
my ($config, $upgrade, $legacy) = @_;
my $dir = "$tmp/".++$serial;
make_path("$dir/config");
my $file = "$dir/config/".($legacy ? 'main.inc.php' : 'config.inc.php');
write_config("$dir/config/config.inc.php.sample", $sample);
write_config($file, $config) if ($upgrade);
return ({ dir => $dir, path => '/roundcube', db => 'mysql_roundcube',
	  phpver => '8.3' }, $file);
}

# install(version, options, [upgrade])
# Invoke the same installation callback used by Virtualmin's CGI and CLI.
sub install
{
my ($version, $opts, $upgrade) = @_;
return main::script_roundcube_install($domain, $version, $opts,
	{ source => 'fixture' }, $upgrade ? { version => '1.6.21', release => 9 } : undef);
}

# read_config(path)
# Read saved PHP as text without executing it.
sub read_config
{
open(my $fh, '<', $_[0]) || die $!;
local $/;
return <$fh>;
}

# write_config(path, content)
# Save fixture input or the installer's generated configuration.
sub write_config
{
open(my $fh, '>', $_[0]) || die $!;
print {$fh} $_[1];
close($fh) || die $!;
}
