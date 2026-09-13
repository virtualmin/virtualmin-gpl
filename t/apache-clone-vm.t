#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once);
use Test::More;
use File::Temp qw(tempfile);

# Opt in before loading Webmin or reading any service configuration.
plan skip_all => 'Set VIRTUALMIN_APACHE_CLONE_VM_TEST=1 on a disposable Virtualmin Apache VM'
	unless ($ENV{'VIRTUALMIN_APACHE_CLONE_VM_TEST'} || '') eq '1';
plan skip_all => 'Requires root on a disposable Linux VM'
	unless $^O eq 'linux' && $< == 0 && $> == 0;

# CLI commands and direct calls must use the same installed Virtualmin code.
$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
open(my $mc, '<', '/etc/webmin/miniserv.conf') or die $!;
my ($root) = map { /^root=(.*)/ ? $1 : () } <$mc>;
close($mc);
die 'Cannot find the Webmin installation' unless $root;
my $module = "$root/virtual-server";
chdir($module) or die $!;
$0 = "$module/apache-clone-vm-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');
plan skip_all => 'Requires the Apache web and SSL features'
	unless $virtual_server::config{'web'} && $virtual_server::config{'ssl'};
foreach my $command (qw(curl timeout)) {
	die "Required command not found: $command" unless has_command($command);
	}
virtual_server::require_apache();
local $main::error_must_die = 1;
virtual_server::set_all_null_print();
note("Testing installed Virtualmin in $module");

# Keep the generated password on the VM, outside command arguments and TAP.
my ($passfh, $passfile) = tempfile('apache-clone-pass-XXXXXX',
	DIR => '/tmp', UNLINK => 1);
open(my $random, '<', '/dev/urandom') or die $!;
my $bytes;
read($random, $bytes, 32) == 32 or die 'Cannot generate fixture password';
close($random);
print $passfh unpack('H*', $bytes) or die $!;
close($passfh) or die $!;
my $tag = sprintf('%x%04x', $$, int(rand(65536)));
my @names = ("apache-clone-source-$tag.invalid", "apache-clone-target-$tag.invalid");
my @users = ("acls$tag", "aclt$tag");
my (%attempted, %saved);
foreach my $i (0, 1) {
	die "Fixture domain already exists: $names[$i]"
		if virtual_server::get_domain_by('dom', $names[$i]);
	die "Fixture account already exists: $users[$i]" if getpwnam($users[$i]);
	}

# Return through cleanup after errors or an interrupted test. Each external
# command also has its own timeout, including commands used during cleanup.
{
	local $SIG{'ALRM'} = sub { die "Apache clone tests timed out\n"; };
	local $SIG{'INT'} = sub { die "Apache clone tests interrupted\n"; };
	alarm(900);
	my $completed = eval { run_tests(); 1; };
	my $error = $@;
	alarm(0);
	if (!$completed) {
		fail('Apache clone integration completed');
		diag($error);
		}
	}
cleanup();
done_testing();

# Create real websites, then exercise configuration and request handling.
sub run_tests
{
$attempted{$names[0]} = 1;
cli('create-domain', '--domain', $names[0], '--user', $users[0],
	'--passfile', $passfile, '--unix', '--dir', '--web', '--ssl',
	'--no-ip6', '--acme-never', '--break-ssl-cert', '--generate-ssl-cert',
	'--no-ssl-redirect', '--content', 'Test Apache clone page',
	'--limits-from-plan', '--no-email', '--no-slaves', '--no-secondaries',
	'--default-cert-owner');
my $source = domain($names[0]);
my $fpm = grep { $_ eq 'fpm' } virtual_server::supported_php_modes($source);
cli('modify-web', '--domain', $names[0], '--mode', $fpm ? 'fpm' : 'none');
$source = domain($names[0]);
virtual_server::obtain_lock_web($source);
my ($virt, $vconf, $conf) = ssl_vhost($source);
apache::save_directive('SSLProtocol', [ '-all +TLSv1.2' ], $vconf, $conf);
flush_file_lines($virt->{'file'});
virtual_server::release_lock_web($source);

# An exact response distinguishes PHP execution from serving its source text.
my $phpfile = virtual_server::public_html_dir($source).'/clone-test.php';
virtual_server::open_tempfile_as_domain_user($source, 'PHP', ">$phpfile");
print_tempfile('PHP', '<?php echo "apache-clone-php-ok";');
virtual_server::close_tempfile_as_domain_user($source, 'PHP');
$attempted{$names[1]} = 1;
cli('clone-domain', '--domain', $names[0], '--newdomain', $names[1],
	'--newuser', $users[1]);
my $target = domain($names[1]);
foreach my $d ($source, $target) {
	subtest "Website $d->{'dom'}" => sub { check_website($d, $fpm); };
	}

# Check lock ownership in this process, before exit can release leaked locks.
foreach my $feature (qw(web ssl)) {
	foreach my $missing (qw(source target)) {
		subtest "$feature clone with missing $missing" => sub {
			check_missing_vhost($source, $target, $feature, $missing);
			};
		}
	}

# PHP mode changes can reparse Apache and hide stale SSL directive references.
cli('modify-web', '--domain', $names[0], '--domain', $names[1], '--mode', 'none');
$source = domain($names[0]);
$target = domain($names[1]);
subtest 'SSL directives survive breaking certificate sharing' => sub {
	check_ssl_relink($source, $target);
	};
}

# Check both vhosts and request PHP through the actual cloned FPM handler.
sub check_website
{
my ($d, $fpm) = @_;
foreach my $port ($d->{'web_port'}, $d->{'web_sslport'}) {
	my ($virt, $vconf) = virtual_server::get_apache_virtual($d->{'dom'}, $port);
	ok($virt, "virtual host exists on port $port") or next;
	is(apache::find_directive('DocumentRoot', $vconf, 1),
		virtual_server::public_html_dir($d), "document root is correct on port $port");
	}
SKIP: {
	skip('PHP-FPM is unavailable', 2) unless $fpm;
	is(virtual_server::get_domain_php_mode($d), 'fpm', 'uses PHP-FPM');
	my ($ok, $endpoint) = virtual_server::get_domain_php_fpm_port($d);
	ok($ok > 0, 'Apache FPM endpoint matches the pool') or diag($endpoint);
	}
foreach my $proto (qw(http https)) {
	my $port = $proto eq 'https' ? $d->{'web_sslport'} : $d->{'web_port'};
	my @curl = ('curl', '--fail', '--silent', '--show-error', '--insecure',
		'--noproxy', '*', '--max-time', '30', '--resolve',
		"$d->{'dom'}:$port:$d->{'ip'}");
	my $url = "$proto://$d->{'dom'}:$port";
	my ($status, $output) = run_command(@curl, "$url/");
	is($status, 0, "$proto page request succeeds") or diag($output);
	like($output, qr/Test Apache clone page/, "$proto serves the copied page");
	SKIP: {
		skip('PHP-FPM is unavailable', 2) unless $fpm;
		($status, $output) = run_command(@curl, "$url/clone-test.php");
		is($status, 0, "$proto PHP request succeeds") or diag($output);
		is($output, 'apache-clone-php-ok', "$proto executes PHP");
		}
	}
}

# Only change names in memory: no real virtual host is removed for these cases.
sub check_missing_vhost
{
my ($source, $target, $feature, $missing) = @_;
$source = { %$source };
$target = { %$target };
my $d = $missing eq 'source' ? $source : $target;
$d->{'dom'} = "missing.$d->{'dom'}";
my $rv = $feature eq 'ssl' ? virtual_server::clone_ssl($target, $source)
			 : virtual_server::clone_web($target, $source);
is($rv, 0, 'missing virtual host fails cloning');
my @held = grep { $main::got_lock_web_file{$_} } keys %main::got_lock_web_file;
is_deeply(\@held, [], 'no counted Apache locks remain');
my @files = ((virtual_server::get_website_file($target))[0],
	(apache::find_httpd_conf())[0]);
my @locked = grep { defined($main::locked_file_list{$_}) } @files;
is_deeply(\@locked, [], 'no Apache file locks remain before process exit');

# Release a regressed lock only after the assertions have observed it.
virtual_server::release_lock_web($target) if @held;
die 'Apache file locks could not be released' if
	grep { defined($main::locked_file_list{$_}) } @files;
}

# Make CA removal shift later directive lines, exposing a stale cached parse.
sub check_ssl_relink
{
my ($source, $target) = @_;
foreach my $d ($source, $target) {
	my ($virt) = ssl_vhost($d);
	$saved{$virt->{'file'}} = read_file_contents($virt->{'file'});
	}
virtual_server::obtain_lock_web($source);
my ($virt, $vconf, $conf) = ssl_vhost($source);
my @dirs = virtual_server::clone_apache_config($vconf);
my ($cert) = grep { $_->{'name'} eq 'SSLCertificateFile' } @dirs;
my ($key) = grep { $_->{'name'} eq 'SSLCertificateKeyFile' } @dirs;
die 'Missing certificate or key directive' unless $cert && $key;
@dirs = grep { $_->{'name'} !~ /^SSL(?:CACertificateFile|CertificateChainFile|CertificateFile|CertificateKeyFile|Protocol)$/ } @dirs;
# Place SSLProtocol immediately after the key so a stale key line number
# overwrites it after CA removal, regardless of the server template's order.
push(@dirs, { 'name' => 'SSLCACertificateFile',
	'value' => $source->{'ssl_cert'}, 'words' => [ $source->{'ssl_cert'} ] },
	$cert, $key, { 'name' => 'SSLProtocol', 'value' => '-all +TLSv1.2',
	'words' => [ '-all', '+TLSv1.2' ] });
$virt->{'members'} = \@dirs;
apache::save_directive_struct($virt, $virt, $conf, $conf);
flush_file_lines($virt->{'file'});
virtual_server::release_lock_web($source);
my $error = apache::test_config();
die "Invalid SSL fixture: $error" if $error;
pass('Apache accepts the SSL fixture');

# Keep the simulated sharing link in memory; the saved domain stays independent.
$target = { %$target, 'ssl_same' => $source->{'id'} };
foreach my $type (virtual_server::list_ssl_file_types()) {
	$target->{'ssl_'.$type} = $source->{'ssl_'.$type};
	}
die 'Fixture certificate unexpectedly covers the clone' if
	virtual_server::check_domain_certificate($target->{'dom'}, $target);
is(virtual_server::clone_ssl($target, $source), 1, 'SSL cloning succeeds');
ok(!$target->{'ssl_same'}, 'the invalid certificate sharing link is broken');

# Read the saved file again, so an intact in-memory copy cannot hide data loss.
apache::flush_config_cache();
my ($newvirt, $newconf) = ssl_vhost($target);
is(apache::find_directive('SSLProtocol', $newconf), '-all +TLSv1.2',
	'preserves SSLProtocol on disk');
is(apache::find_directive('SSLCertificateFile', $newconf, 1),
	virtual_server::apache_combined_cert($target) ?
		$target->{'ssl_combined'} : $target->{'ssl_cert'},
	'uses the target certificate path');
$error = apache::test_config();
ok(!$error, 'Apache configuration remains valid') or diag($error);
}

# External commands run quietly, without stdin, and cannot wait indefinitely.
sub run_command
{
my $command = join(' ', map { quote_path($_) }
	('timeout', '--kill-after=10s', '180s', @_));
my $output = backquote_command("$command </dev/null 2>&1");
return ($?, $output);
}

# A feature can print a failure yet let the CLI exit successfully.
sub cli
{
my ($command, @args) = @_;
my ($status, $output) = run_command($^X, "$module/$command.pl", @args);
die "$command failed (status $status):\n$output" if $status ||
	$output =~ /Call Stack Trace|(?:source|destination) Apache configuration not found/;
}

# CLI subprocesses change domain records and Apache files behind our caches.
sub domain
{
my ($name) = @_;
refresh_caches();
return virtual_server::get_domain_by('dom', $name) || die "Missing domain $name";
}

# Domain maps have a separate Webmin cache, populated by the collision checks.
# Refresh it after CLI changes so lookups and cleanup see newly created domains.
sub refresh_caches
{
virtual_server::flush_virtualmin_caches();
foreach my $file (values %virtual_server::get_domain_by_maps) {
	delete($main::read_file_cache{$file});
	delete($main::read_file_missing{$file});
	}
apache::flush_config_cache();
}

# SSL fixture preparation requires an actual parsed virtual host.
sub ssl_vhost
{
my ($d) = @_;
my @virt = virtual_server::get_apache_virtual($d->{'dom'}, $d->{'web_sslport'});
die "Missing SSL virtual host for $d->{'dom'}" unless $virt[0];
return @virt;
}

# Restore potentially damaged vhosts before asking the CLI to delete fixtures.
sub cleanup
{
unlock_all_files();
my $restored = eval {
	if (%saved) {
		my ($mainconf) = apache::find_httpd_conf();
		# Match obtain_lock_web's order: website files, then main config.
		lock_file($_) foreach grep { $_ ne $mainconf } sort keys %saved;
		lock_file($mainconf);
		foreach my $file (sort keys %saved) {
			unflush_file_lines($file);
			write_file_contents($file, $saved{$file});
			}
		unlock_all_files();
		apache::flush_config_cache();
		}
	1;
	};
my $error = $@;
unlock_all_files();
if (!$restored) {
	fail('restores Apache configuration before cleanup');
	diag($error, "Fixtures left for manual cleanup: @names");
	return;
	}
foreach my $i (reverse(0, 1)) {
	my $name = $names[$i];
	next unless $attempted{$name};
	refresh_caches();
	if (virtual_server::get_domain_by('dom', $name)) {
		my ($status, $output) = run_command($^X, "$module/delete-domain.pl",
			'--domain', $name);
		is($status, 0, "deletes $name") or diag($output);
		}
	refresh_caches();
	ok(!virtual_server::get_domain_by('dom', $name), "$name is removed");
	ok(!defined(getpwnam($users[$i])), "Unix account $users[$i] is removed");
	}
}
