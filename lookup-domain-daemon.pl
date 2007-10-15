#!/usr/local/bin/perl
# A server process that listens on port 11000 for requests from
# lookup-domain-client.pl, and returns the following information for each
# user:
# domain ID
# domain name
# spam-enabled?
# using-spamc?
# quota-remaining (UNLIMITED for no quota)

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/lookup-domain-daemon.pl";
require './virtual-server-lib.pl';
$< == 0 || die "lookup-domain-daemon.pl must be run as root";
use POSIX;
use Socket;

# Attempt to open the socket
$proto = getprotobyname('tcp');
$proto || die "Failed to get tcp protocol";
socket(MAIN, PF_INET, SOCK_STREAM, $proto) ||
	die "Failed to create socket : $!";
setsockopt(MAIN, SOL_SOCKET, SO_REUSEADDR, pack("l", 1));
bind(MAIN, pack_sockaddr_in(11000, inet_aton("127.0.0.1"))) ||
	die "Failed to bind to localhost port 11000";
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

# Loop forever, accepting requests from clients
while(1) {
	# Get a connection
	$acptaddr = accept(SOCK, MAIN);
	next if (!$acptaddr);
	binmode(SOCK);
	($peerp, $peera) = unpack_sockaddr_in($acptaddr);

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
		next;
		}
	@users = &list_domain_users($d, 0, 1, 0, 1);
	($user) = grep { $_->{'user'} eq $username ||
			 &replace_atsign($_->{'user'}) eq $username } @users;
	if (!$user) {
		# Failed to find user again!
		&send_response(undef, undef);
		next;
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
	local $qmode = &mail_under_home() && &has_home_quotas() ? "home" :
		       &has_mail_quotas() ? "mail" : undef;
	local ($quota, $uquota);
	if ($qmode eq "home") {
		($quota, $uquota) = ($user->{'quota'}, $user->{'uquota'});
		}
	elsif ($qmode eq "mail") {
		($quota, $uquota) = ($user->{'mquota'}, $user->{'umquota'});
		}
	local $client = &get_domain_spam_client($d);
	print join("\t", $d->{'id'},
			 $d->{'dom'},
			 $d->{'spam'} && !$user->{'nospam'},
			 ($client eq "spamc" ? 1 : 0),
			 ($quota ? ($quota - $uquota)*&quota_bsize($qmode)
				 : "UNLIMITED"),
		  ),"\n";
	print STDERR "[$now] user=$username dom=$d->{'dom'} spam=$d->{'spam'} client=$client quota=$quota uquota=$uquota\n";
	}
else {
	print "\t\t\t\t\t\n";
	print STDERR "[$now] user=$username NOUSER\n";
	}
close(SOCK);

# Truncate the log if too big (10MB)
local @st = stat($daemon_logfile);
if ($st[7] > 10*1024*1024) {
	close(STDERR);
	open(STDERR, ">$daemon_logfile");
	}
}

