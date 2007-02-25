#!/usr/local/bin/perl
# create-user.pl
# Adds a new mailbox user, based on command-line parameters

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/create-user.pl";
require './virtual-server-lib.pl';
$< == 0 || die "create-user.pl must be run as root";

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$username = lc(shift(@ARGV));
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--real" || $a eq "--desc") {
		$real = shift(@ARGV);
		}
	elsif ($a eq "--ftp") {
		$ftp = 1;
		}
	elsif ($a eq "--jailed-ftp") {
		$config{'jail_shell'} || usage();
		$ftp = 2;
		}
	elsif ($a eq "--noemail") {
		$noemail++;
		}
	elsif ($a eq "--extra") {
		local $extra = shift(@ARGV);
		push(@extra, $extra);
		}
	elsif ($a eq "--quota") {
		$quota = shift(@ARGV);
		}
	elsif ($a eq "--mail-quota") {
		$mquota = shift(@ARGV);
		}
	elsif ($a eq "--qmail-quota") {
		$qquota = shift(@ARGV);
		}
	elsif ($a eq "--mysql") {
		$db = shift(@ARGV);
		push(@dbs, { 'type' => 'mysql', 'name' => $db });
		}
	elsif ($a eq "--group") {
		$group = shift(@ARGV);
		push(@groups, $group);
		}
	elsif ($a eq "--disable") {
		$disable = 1;
		}
	elsif ($a eq "--web") {
		$web = 1;
		}
	elsif ($a eq "--home") {
		$home = shift(@ARGV);
		}
	else {
		&usage();
		}
	}
$domain && $username && $pass || &usage();

# Get the initial user
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$user = &create_initial_user($d, 0, $web);

# Make sure all needed args are set
if ($user->{'unix'} && !$user->{'noquota'}) {
	if (&has_home_quotas()) {
		$quota =~ /^\d+$/ || &usage();
		}
	if (&has_mail_quotas()) {
		$mquota =~ /^\d+$/ || &usage();
		}
	}
if ($user->{'mailquota'}) {
	!$qquota || $qquota =~ /^\d+$/ || usage();
	}
$username =~ /^[^ \t:]+$/ || usage($text{'user_euser'});
if ($user->{'person'}) {
	$real =~ /^[^:]*$/ || usage($text{'user_ereal'});
	}
foreach $e (@extra) {
	$user->{'noextra'} && &usage("This user cannot have extra email addresses");
	$e = lc($e);
	if ($e =~ /^([^\@ \t]+$)$/) {
		$e = "$e\@$d->{'dom'}";
		}
	if ($e !~ /^(\S+)\@(\S+)$/) {
		usage(&text('user_eextra1', $e));
		}
	local ($eu, $ed) = ($1, $2);
	local $edom = &get_domain_by("dom", $ed);
	$edom && $edom->{'mail'} || usage(&text('user_eextra2', $ed));
	}

@alldbs = &domain_databases($d);
foreach $db (@dbs) {
	($got) = grep { $_->{'type'} eq $db->{'type'} &&
		        $_->{'name'} eq $db->{'name'} } @alldbs;
	$got || usage("Database $db->{'name'} does not exist in domain");
	}

%cangroups = map { $_, 1 } &allowed_secondary_groups($d);
foreach $g (@groups) {
	$cangroups{$g} ||
		&usage("Group $g is not allowed for this virtual server");
	}

# Build taken lists
&lock_user_db();
&build_taken(\%taken, \%utaken);

# Construct user object
if ($user->{'unix'} && !$user->{'webowner'}) {
	$user->{'uid'} = &allocate_uid(\%taken);
	}
else {
	$user->{'uid'} = $d->{'uid'};
	}
$user->{'gid'} = $d->{'gid'} || $d->{'ugid'};
if ($user->{'person'}) {
	$user->{'real'} = $real;
	}
if ($user->{'unix'}) {
	$user->{'shell'} = $ftp == 1 ? $config{'ftp_shell'} :
			   $ftp == 2 ? $config{'jail_shell'} :
				       $config{'shell'};
	}
if (!$user->{'fixedhome'}) {
	if (defined($home)) {
		# Home was set manually
		if ($home !~ /^\//) {
			$home = "$d->{'home'}/$home";
			}
		$user->{'home'} = $home;
		if (-d $home && !$user->{'nocreatehome'}) {
			&usage(&text('user_emkhome', $home));
			}
		}
	elsif ($user->{'webowner'}) {
		# Automatic public_html home
		$user->{'home'} = &public_html_dir($d);
		}
	else {
		# Automatic home under homes
		$user->{'home'} = "$d->{'home'}/$config{'homes_dir'}/$username";
		}
	}
$user->{'passmode'} = 3;
$user->{'plainpass'} = $pass;
$user->{'pass'} = &encrypt_user_password($user, $pass);
if ($disable) {
	&set_pass_disable($user, 1);
	}
if (!$user->{'noextra'}) {
	$user->{'extraemail'} = \@extra;
	}
if (($utaken{$username} || $config{'append'}) && !$user->{'noappend'}) {
	$user->{'user'} = &userdom_name($username, $d);
	}
else {
	$user->{'user'} = $username;
	}
if (!$noemail && !$user->{'noprimary'}) {
	$user->{'email'} = "$username\@$d->{'dom'}"
	}
if ($user->{'mailquota'}) {
	$user->{'qquota'} = $qquota;
	}
if ($user->{'unix'} && !$user->{'noquota'}) {
	$user->{'quota'} = $quota;
	$user->{'mquota'} = $mquota;
	}
$user->{'dbs'} = \@dbs if (@dbs);
$user->{'secs'} = \@groups;

if ($user->{'unix'}) {
	# Check for a Unix clash
	if ($utaken{$user->{'user'}} ||
	    &check_clash($username, $d->{'dom'})) {
		usage($text{'user_eclash'});
		}
	}

# Check for clash within this domain
($clash) = grep { $_->{'user'} eq $username &&
		  $_->{'unix'} == $user->{'unix'} } @users;
$clash && &error($text{'user_eclash2'});

if (!$user->{'noextra'}) {
	# Check if any extras clash
	foreach $e (@extra) {
		$e =~ /^(\S+)\@(\S+)$/;
		if (&check_clash($1, $2)) {
			usage(&text('user_eextra4', $e));
			}
		}
	}

# Check if the name is too long
if ($lerr = &too_long($user->{'user'})) {
	usage($lerr);
	}

# Create the user and virtusers and alias
&create_user($user, $d);

if ($user->{'home'} && !$user->{'nocreatehome'}) {
	# Create his homedir
	&create_user_home($user, $d);
	}

# Create an empty mail file, if needed
if ($user->{'email'} && !$user->{'nomailfile'}) {
	&create_mail_file($user);
	}

# Send an email upon creation
@erv = &send_user_email($d, $user, undef, 0);

print "User $user->{'user'} created successfully\n";
&unlock_user_db();

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds a new mailbox user to an existing Virtualmin domain.\n";
print "\n";
print "usage: create-user.pl    --domain domain.name\n";
print "                         --user new-username\n";
print "                         --pass password-for-new-user\n";
if (&has_home_quotas()) {
	print "                         --quota quota-in-blocks\n";
	}
if (&has_mail_quotas()) {
	print "                         --mail-quota quota-in-blocks\n";
	}
if (&has_server_quotas()) {
	print "                         --qmail-quota quota-in-bytes\n";
	}
if (!$user || $user->{'person'}) {
	print "                        [--real real-name-for-new-user]\n";
	}
if (!$user || $user->{'unix'}) {
	print "                        [--ftp]\n";
	if ($config{'jail_ftp'}) {
		print "                        [--jail-ftp]\n";
		}
	}
print "                        [--noemail]\n";
print "                        [--extra email.address\@some.domain]\n";
print "                        [--mysql db] ...\n";
print "                        [--group name] ...\n";
print "                        [--web]\n";
exit(1);
}
