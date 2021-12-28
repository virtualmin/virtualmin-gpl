#!/usr/local/bin/perl

=head1 lookup-domain-daemon.pl

A background process for looking up user details.

This is a server process that listens on port 11000 for requests from
C<lookup-domain.pl>. Each request is just a username followed by a newline,
and the response is a line containing the following tab-separated fields :

domain ID
domain name
spam-enabled?
using-spamc?
quota-remaining (UNLIMITED for no quota)

Generally, there is no need for you to ever run this script manually - it is
typically started by C</etc/init.d/lookup-domain>.

=cut

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*)\/[^\/]+$/) {
	chdir($pwd = $1);
	}
else {
	chop($pwd = `pwd`);
	}
$0 = "$pwd/lookup-domain-daemon.pl";
$no_virtualmin_plugins = 1;
require './virtual-server-lib.pl';
$< == 0 || die "lookup-domain-daemon.pl must be run as root";
use POSIX;
use Socket;

# Parse command line
$port = $config{'lookup_domain_port'} || $lookup_domain_port;
while(@ARGV) {
	my $a = shift(@ARGV);
	if ($a eq "--port") {
		$port = shift(@ARGV);
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Attempt to open the socket
$proto = getprotobyname('tcp');
$proto || die "Failed to get tcp protocol";
socket(MAIN, PF_INET, SOCK_STREAM, $proto) ||
	die "Failed to create socket : $!";
setsockopt(MAIN, SOL_SOCKET, SO_REUSEADDR, pack("l", 1));
bind(MAIN, pack_sockaddr_in($port, inet_aton("127.0.0.1"))) ||
	die "Failed to bind to localhost port $port";
listen(MAIN, SOMAXCONN);

# Split from controlling terminal
if (fork()) { exit; }
setsid();
open(STDIN, "</dev/null");
open(STDOUT, ">/dev/null");
$daemon_logfile = "$ENV{'WEBMIN_VAR'}/lookup-domain-daemon.log";
open(STDERR, ">>$daemon_logfile");

# Write out the PID file
open(PIDFILE, ">$ENV{'WEBMIN_VAR'}/lookup-domain-daemon.pid");
printf PIDFILE "%d\n", getpid();
close(PIDFILE);

if (!$config{'lookup_domain_serial'}) {
	$SIG{'CHLD'} = sub { wait(); };
	}

# Loop forever, accepting requests from clients
while(1) {
	# Get a connection
	$acptaddr = accept(SOCK, MAIN);
	next if (!$acptaddr);
	binmode(SOCK);
	($peerp, $peera) = unpack_sockaddr_in($acptaddr);

	# Truncate the log if too big (10MB)
	local @st = stat($daemon_logfile);
	if ($st[7] > 10*1024*1024) {
		close(STDERR);
		open(STDERR, ">$daemon_logfile");
		}

	if ($config{'lookup_domain_serial'}) {
		# Single-threaded mode
		&handle_one_request();
		}
	else {
		# Give up now if too many child processes already,
		# to prevent DDOS
		if (@childpids > 50) {
			print STDERR "Too many child processes are ",
				     "running already\n";
			close(SOCK);
			next;
			}

		# Fork a sub-process to handle this request
		$pid = fork();
		if ($pid < 0) {
			print STDERR "Fork failed : $!\n";
			close(SOCK);
			next;
			}
		elsif (!$pid) {
			# Close the main socket
			close(MAIN);

			# Return child cleanup policy to default, so
			# that sub-command exit statuses can be collected
			$SIG{'CHLD'} = 'DEFAULT';

			# If lookup takes more than 60 seconds, give up .. since
			# the client only waits 30
			alarm(60);

			&handle_one_request();
			exit(0);
			}
		
		# Maintain list of child processes
		push(@childpids, $pid);
		local $expid;
		do {	$expid = waitpid(-1, WNOHANG);
			} while($expid != 0 && $expid != -1);
		@childpids = grep { kill(0, $_) } @childpids;
		}
	}

sub handle_one_request
{
# Read the username
select(SOCK); $| = 1;
$username = <SOCK>;
$username =~ s/\r|\n//g;

# Find the user
&flush_virtualmin_caches();
&flush_webmin_caches();
$d = &get_user_domain($username);
if (!$d) {
	# No such user!
	&send_response(undef, undef);
	return;
	}
@users = &list_domain_users($d, 0, 1, 0, 1);
($user) = grep { $_->{'user'} eq $username ||
		 &replace_atsign($_->{'user'}) eq $username }
	       @users;
if (!$user) {
	# Failed to find user again!
	&send_response(undef, undef);
	return;
	}

# Send back status
&send_response($d, $user);
}

# send_response(&domain, &user)
sub send_response
{
local ($d, $user) = @_;
local $now = localtime(time());
if ($d && $user) {
	# Get the user's quota
	local $qmode = &mail_under_home() && &has_home_quotas() ? "home" :
		       &has_mail_quotas() ? "mail" : undef;
	local ($quota, $uquota);
	if ($qmode eq "home") {
		($quota, $uquota) = ($user->{'quota'}, $user->{'uquota'});
		}
	elsif ($qmode eq "mail") {
		($quota, $uquota) = ($user->{'mquota'}, $user->{'umquota'});
		}
	local $quotadiff = $quota ? ($quota - $uquota) : undef;

	# Get the domain's quota, in case it is less
	local $qd = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
	local $dquota = $qd->{'quota'};
	local $duquota;
	if ($dquota && &has_group_quotas()) {
		($duquota) = &get_domain_quota($qd, 0);
		local $dquotadiff = $dquota - $duquota;
		if ($dquotadiff < $quotadiff) {
			# Domain has less space free than user!
			$quotadiff = $dquotadiff;
			}
		}

	# If using only soft quotas, disable all quota checking
	if (!$config{'hard_quotas'}) {
		$quotadiff = undef;
		}

	local $client = &get_domain_spam_client($d);
	print join("\t", $d->{'id'},
			 $d->{'dom'},
			 $d->{'spam'} && !$user->{'nospam'},
			 ($client eq "spamc" ? 1 : 0),
			 (defined($quotadiff) ? $quotadiff*&quota_bsize($qmode)
					      : "UNLIMITED"),
		  ),"\n";
	seek(STDERR, 0, 2);
	print STDERR "[$now] user=$username dom=$d->{'dom'} spam=$d->{'spam'} client=$client quota=$quota uquota=$uquota dquota=$dquota duquota=$duquota\n";
	}
else {
	print "\t\t\t\t\t\n";
	seek(STDERR, 0, 2);
	print STDERR "[$now] user=$username NOUSER\n";
	}
close(SOCK);

}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Daemon process for looking up Virtualmin users.\n";
print "\n";
print "usage: lookup-domain-daemon.pl\n";
exit(1);
}

