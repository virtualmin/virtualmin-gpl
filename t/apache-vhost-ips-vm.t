#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once);
use Test::More;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use POSIX qw(WNOHANG setsid);

# Opt in on a disposable VM before reading service configuration or starting Apache.
plan skip_all => 'Set VIRTUALMIN_APACHE_VHOST_VM_TEST=1 on a disposable Apache VM'
	unless ($ENV{'VIRTUALMIN_APACHE_VHOST_VM_TEST'} || '') eq '1';
plan skip_all => 'Requires root on a disposable Linux VM'
	unless $^O eq 'linux' && $< == 0 && $> == 0;

# Load installed Virtualmin and its Apache parser. A candidate feature file may
# be loaded in this process without changing the installed module.
$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
open(my $mc, '<', '/etc/webmin/miniserv.conf') or die $!;
my ($root) = map { /^root=(.*)/ ? $1 : () } <$mc>;
close($mc);
die 'Cannot find Webmin' unless $root;
chdir("$root/virtual-server") or die $!;
$0 = "$root/virtual-server/apache-vhost-ips-vm-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');
virtual_server::require_apache();
if ($ENV{'VIRTUALMIN_APACHE_VHOST_SOURCE'}) {
	# Only this test process sees the candidate implementation.
	package virtual_server;
	no warnings 'redefine';
	do $ENV{'VIRTUALMIN_APACHE_VHOST_SOURCE'} or die "$@ $!";
	}
my $httpd = apache::find_httpd() || die 'Cannot find Apache';
my $other6 = virtual_server::get_default_ip6();
die 'Requires a non-loopback IPv6 address on the VM' unless $other6 && $other6 ne '::1';
my ($ip, $ip6, $other) = ('127.0.0.1', '::1', '127.0.0.2');

# Use real shared-address checks with process-local defaults. No network or
# Virtualmin settings are saved, and Linux already routes the IPv4 loopback range.
local $virtual_server::config{'defip'} = $ip;
local $virtual_server::config{'defip6'} = $ip6;
local $virtual_server::config{'sharedips'} = '';
local $virtual_server::config{'sharedip6s'} = '';
die 'The fixture IPv6 address is already shared by a reseller'
	if virtual_server::is_shared_ip($other6);
my $work = tempdir('apache-vhost-ips-XXXXXX', DIR => '/tmp', CLEANUP => 1);
chmod(0755, $work) or die $!;
my $config = "$work/httpd.conf";
my $cert = "$work/test.crt";
my $key = "$work/test.key";
my $user = defined(getpwnam('apache')) ? 'apache' : 'www-data';
my $server_root = -d '/etc/httpd' ? '/etc/httpd' : '/etc/apache2';
my $modules = -d '/etc/httpd/conf.modules.d' ?
	'/etc/httpd/conf.modules.d/*.conf' : '/etc/apache2/mods-enabled/*.load';
my @ports = (18080, 18443);
my $pid;

# Stop only the standalone test server, including after an assertion or signal.
END { stop_apache() if $pid; }
local $SIG{'INT'} = sub { die "Interrupted\n"; };
local $SIG{'TERM'} = sub { die "Terminated\n"; };
my ($status, $output) = run_command('openssl', 'req', '-x509', '-newkey',
	'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=first.invalid',
	'-keyout', $key, '-out', $cert);
die "Cannot create fixture certificate: $output" if $status;

# Cover different creation orders, both mixed layouts, and existing explicit groups.
my $dual = { ip => $ip, ip6 => $ip6 };
my @cases = (
	[ 'wildcard defaults', [ $dual, $dual ] ],
	[ 'IPv6-only first', [ { ip6 => $ip6 }, $dual ] ],
	[ 'reported non-shared IPv6 sequence', [
		{ ip => $ip, ip6 => $other6 }, { ip => $ip, ip6 => $other6 }, $dual ] ],
	[ 'later dedicated IPv6', [ $dual,
		{ ip => $ip, ip6 => $other6, virt6 => 1 }, $dual ] ],
	[ 'later dedicated IPv4', [ $dual,
		{ ip => $other, ip6 => $ip6, virt => 1 }, $dual ] ],
	[ 'existing explicit IPv4 with wildcard IPv6', [ $dual, $dual ], [ $ip, '*' ] ],
	[ 'existing wildcard IPv4 with explicit IPv6', [ $dual, $dual ], [ '*', "[$ip6]" ] ],
	[ 'existing explicit addresses', [ $dual, $dual ], [ $ip, "[$ip6]" ] ],
);
foreach my $case (@cases) {
	subtest $case->[0] => sub {
		make_config($case->[1], $case->[2]);
		my ($status, $output) = run_command($httpd, '-t', '-f', $config);
		is($status, 0, 'Apache accepts the generated configuration') or die $output;
		start_apache();
		foreach my $i (0 .. $#{$case->[1]}) {
			my $d = $case->[1][$i];
			foreach my $port (@ports) {
				my $scheme = $port == 18080 ? 'http' : 'https';
				foreach my $field (qw(ip ip6)) {
					next unless $d->{$field};
					my $address = $field eq 'ip6' ? "[$d->{$field}]" : $d->{$field};
					my ($status, $body) = run_command('curl', '--noproxy', '*',
						'-ksS', '--fail', '--max-time', '10', '--resolve',
						"site$i.invalid:$port:$address",
						"$scheme://site$i.invalid:$port/index.html");
					is($status, 0, "$scheme site$i on $field responds") or diag($body);
					is($body, "site$i", "$scheme site$i on $field reaches its own host");
					}
				}
			}
		stop_apache();
		};
	}
done_testing();

# make_config(domains, [first-addresses])
# Append each generated host, then reparse the file before creating the next.
# Optional first-addresses simulate a pre-existing configuration.
sub make_config
{
my ($domains, $first) = @_;
open(my $fh, '>', $config) or die $!;
print $fh "ServerRoot $server_root\nInclude $modules\nTypesConfig /etc/mime.types\n",
	"User $user\nGroup $user\nServerName fixture.invalid\n",
	"DefaultRuntimeDir $work\nPidFile $work/httpd.pid\n",
	"ErrorLog $work/error.log\nLogLevel warn\nSSLSessionCache none\n";
foreach my $port (@ports) {
	# Bind only fixture addresses, leaving the normal Apache service untouched.
	print $fh "Listen $ip:$port\nListen $other:$port\n",
		"Listen [$ip6]:$port\nListen [$other6]:$port\n";
	}
close($fh) or die $!;
foreach my $port (@ports) {
	foreach my $i (0 .. $#$domains) {
		my $d = $domains->[$i];
		my @conf = apache::get_config_file($config, {});
		my $star4 = $d->{'ip'} ?
			virtual_server::add_name_virtual($d, \@conf, $port, 1, $d->{'ip'}) : undef;
		my $star6 = $d->{'ip6'} ?
			virtual_server::add_name_virtual($d, \@conf, $port, 1, $d->{'ip6'}) : undef;
		my $value = !$i && $first ? join(' ', map { "$_:$port" } @$first) :
			virtual_server::get_apache_vhost_ips($d, $star4, $star6, $port);
		my $dir = "$work/site$i";
		mkdir($dir, 0755) unless -d $dir;
		open(my $page, '>', "$dir/index.html") or die $!;
		print $page "site$i";
		close($page) or die $!;
		open($fh, '>>', $config) or die $!;
		print $fh "<VirtualHost $value>\nServerName site$i.invalid\n",
			"DocumentRoot $dir\n<Directory $dir>\nRequire all granted\n</Directory>\n";
		if ($port == 18443) {
			# All hosts use a disposable certificate; only routing is under test.
			print $fh "SSLEngine on\nSSLCertificateFile $cert\nSSLCertificateKeyFile $key\n";
			}
		print $fh "</VirtualHost>\n";
		close($fh) or die $!;
		}
	}
}

# start_apache()
# Start an isolated process group and wait at most five seconds for its listener.
sub start_apache
{
$pid = fork();
die "Cannot fork: $!" unless defined($pid);
if (!$pid) {
	# Redirect all child streams to VM-local files before starting the server.
	setsid() != -1 or die $!;
	open(STDIN, '<', '/dev/null') or die $!;
	open(STDOUT, '>>', "$work/process.log") or die $!;
	open(STDERR, '>&', \*STDOUT) or die $!;
	exec($httpd, '-f', $config, '-DFOREGROUND');
	die "Cannot execute Apache: $!";
	}
foreach (1 .. 50) {
	if (waitpid($pid, WNOHANG) == $pid) {
		# The child has already exited; do not signal a potentially reused PID.
		undef($pid);
		die read_file_contents("$work/error.log").read_file_contents("$work/process.log");
		}
	my $socket = IO::Socket::INET->new(PeerAddr => $ip, PeerPort => 18080, Timeout => 1);
	if ($socket) {
		# A listener from our running process is ready for HTTP and TLS requests.
		close($socket);
		return;
		}
	select(undef, undef, undef, 0.1);
	}
die 'Standalone Apache did not start';
}

# stop_apache()
# Stop the test process group and reap the parent, with a bounded fallback.
sub stop_apache
{
return unless $pid;
kill('TERM', -$pid);
foreach (1 .. 100) {
	if (waitpid($pid, WNOHANG) == $pid) {
		# Apache and its workers have stopped normally.
		undef($pid);
		return;
		}
	select(undef, undef, undef, 0.1);
	}
kill('KILL', -$pid);
waitpid($pid, 0);
undef($pid);
}

# run_command(command, args...)
# Capture command output without stdin and bound every external command.
sub run_command
{
my $command = join(' ', map { quote_path($_) }
	('timeout', '--kill-after=5s', '30s', @_));
my $output = backquote_command("$command </dev/null 2>&1");
return ($?, $output);
}
