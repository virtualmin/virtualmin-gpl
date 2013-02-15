#!/usr/local/bin/perl
# Returns the domain ID for some user, if the domain has spam enabled and
# if the user is not approaching his quota

$no_acl_check++;
@ARGV == 1 || die "usage: lookup-domain.pl <username>";
use Socket;

# Get the message size
while($got = read(STDIN, $buf, 1024)) {
	$size += $got;
	}
$margin = $size*2+5*1024*1024;
$quota_margin = 100*1024;    # Bounce if message would get this close to quota

# First, try connecting to the lookup-domain-daemon.pl process. Only wait for
# 30 seconds, in case it has hung.
$connect_timed_out = 0;
local $SIG{ALRM} = sub { $connect_timed_out = 1 };
socket(DAEMON, PF_INET, SOCK_STREAM, getprotobyname("tcp"));
alarm(30);
$rv = connect(DAEMON, pack_sockaddr_in(11000, inet_aton("127.0.0.1")));
if ($rv) {
	select(DAEMON); $| = 1; select(STDOUT);
	print DAEMON $ARGV[0],"\n";
	$fromdaemon = <DAEMON>;
	$fromdaemon =~ s/\r|\n//g;
	close(DAEMON);
	}
alarm(0);
if ($connect_timed_out) {
	print STDERR "Timeout connecting to lookup-domain-daemon.pl\n";
	}
if ($fromdaemon && !$connect_timed_out) {
	# We have an answer from the server process
	($did, $dname, $spam, $spamc, $quotaleft) = split(/\t/, $fromdaemon);
	if ($did && $quotaleft ne "UNLIMITED" &&
	    $quotaleft-$size-$quota_margin <= 0) {
		# Quota has been reached, bounce mail
		print STDERR "Disk quota for $ARGV[0] has been reached.\n";
		print $did,"\n";
		exit(73);
		}
	elsif (!$did || !$spam) {
		# No such user, or user's domain doesn't have spam enabled -
		# don't do spam check
		}
	elsif ($spamc || $quotaleft eq "UNLIMITED") {
		# Domain is using spamc, or user has no quota, or quota disabled
		# Do spam check.
		print $did,"\n";
		}
	elsif ($quotaleft < $margin) {
		# Too close to quota - don't check for spam, so return
		# no domain ID
		}
	else {
		# Do spam check
		print $did,"\n";
		}
	exit(0);
	}

# Open the cache DBM
$cachefile = "$ENV{'WEBMIN_VAR'}/lookup-domain-cache";
eval "use SDBM_File";
dbmopen(%usercache, $cachefile, 0700);
eval "\$usercache{'1111111111'} = 1";
if ($@) {
	dbmclose(%usercache);
	eval "use NDBM_File";
	dbmopen(%usercache, $cachefile, 0700);
	}

# Check our cache first, in case we have just done this user
$now = time();
if (defined($usercache{$ARGV[0]})) {
	($cachespam, $cachequota, $cacheuquota, $cachetime, $cacheclient) =
		split(/ /, $usercache{$ARGV[0]});
	$cacheclient ||= "spamassassin";
	if ($now - $cachetime < 60*60) {
		if ($cachequota &&
		    $cacheuquota+$size+$quota_margin >= $cachequota) {
			# At or over quota. Actually re-check for real though,
			# to avoid bouncing mail un-necessarily
			}
		elsif (!$cachespam) {
			# Domain doesn't have spam enabled, so don't do check
			$cacheuquota += $size;
			&update_cache();
			exit(0);
			}
		elsif ($cacheclient eq "spamc") {
			# Using spamc, so quotas don't matter
			$cacheuquota += $size;
			&update_cache();
			print $cachespam,"\n";
			exit(0);
			}
		elsif ($cachequota && $cacheuquota+$margin >= $cachequota) {
			# User is over quota, so don't do spam check
			$cacheuquota += $size;
			$cacheuquota = $cachequota
				if ($cacheuquota > $cachequota);
			&update_cache();
			exit(0);
			}
		else {
			# User is under quota, so proceed
			$cacheuquota += $size;
			&update_cache();
			print $cachespam,"\n";
			exit(0);
			}
		}
	}

# Lookup the user for real
do './virtual-server-lib.pl';
$d = &get_user_domain($ARGV[0]);
if (!$d || !$d->{'spam'}) {
	$cachespam = $cachequota = $cacheuquota = 0;
	$cachetime = $now;
	&update_cache();
	exit(0);
	}

# See what kind of quotas are relevant
$qmode = &mail_under_home() && &has_home_quotas() ? "home" :
	 &has_mail_quotas() ? "mail" : undef;
if (!$qmode) {
	# None .. so run spam checks
	$cachespam = $d->{'id'};
	$cachequota = $cacheuquota = 0;
	$cachetime = $now;
	&update_cache();
	print "$d->{'id'}\n";
	exit(0);
	}

# Check if the domain is using spamc or spamassassin
$cacheclient = &get_domain_spam_client($d);

# Check if the user is approaching his quota
@users = &list_domain_users($d, 0, 1, 0, 1);
($user) = grep { $_->{'user'} eq $ARGV[0] ||
		 &replace_atsign($_->{'user'}) eq $ARGV[0] } @users;
if (!$user) {
	# Couldn't find him?! So do the spam check
	$cachespam = $d->{'id'};
	$cachequota = $cacheuquota = 0;
	$cachetime = $now;
	&update_cache();
	print "$d->{'id'}\n";
	exit(0);
	}
if ($qmode eq "home") {
	($quota, $uquota) = ($user->{'quota'}, $user->{'uquota'});
	}
else {
	($quota, $uquota) = ($user->{'mquota'}, $user->{'umquota'});
	}
$bsize = &quota_bsize($qmode);
$quota *= $bsize;
$uquota *= $bsize;
if ($quota && $uquota+$size+$quota_margin >= $quota) {
	# Over quota - intentionally fail
	print STDERR "Disk quota for $user->{'user'} of $quota blocks has been reached.\n";
	print "$d->{'id'}\n";
	exit(73);
	}
elsif ($user->{'nospam'}) {
	# Spam filtering disabled for this user
	$cachespam = 0;
	}
elsif ($cacheclient eq "spamc") {
	# Using spamc, so quotas don't matter since spam processing is run
	# by a daemon
	print "$d->{'id'}\n";
	}
elsif ($quota && $uquota+$margin >= $quota) {
	# Close to quota - don't return domain ID, to disable spam checking
	}
else {
	# Under quota ... do the spam check
	print "$d->{'id'}\n";
	}
$cachespam = $d->{'id'};
$cachequota = $quota;
$cacheuquota = $uquota;
$cachetime = $now;
&update_cache();
exit(0);

sub update_cache
{
$usercache{$ARGV[0]} = join(" ", $cachespam, $cachequota, $cacheuquota, $cachetime, $cacheclient);
dbmclose(%usercache);
}

