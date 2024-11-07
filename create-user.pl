#!/usr/local/bin/perl

=head1 create-user.pl

Create a mail, FTP or database user

This program adds a new user to an existing virtual server. It is typically
called with parameters like :

  virtualmin create-user --domain foo.com --user jimmy --pass smeg --quota 1024 --real "Jimmy Smith"

This command would add a user to the server I<foo.com> named I<jimmy> with password
I<smeg> and a disk quota of 1MB. The actual POP3 and FTP username may end up as
jimmy.foo, depending on whether or not domain suffix are always appended to
usernames, and what suffix format is used. However, you can force use of the
specified username with the C<--noappend> flag.

The C<--ftp> option can be used to give the new user an FTP login as well - by
default, he will only be given an email account. The C<--noemail> option turns
off the default email account, which is useful for creating FTP or
database-only users.

The C<--db-only> flag is used to create a database-only user, with no Unix user,
email or FTP access. The C<--webserver-only> flag is used to create a webserver-only
user, with no Unix user, email, database or FTP access, and the C<--webserver-dir>
option can be used to specify directories to which the webserver user will have access
to. This option can be given multiple times to specify multiple directories.

The new user can be granted access to MySQL databases associated with the
virtual server with the C<--mysql> option, which must be followed by a database
name. This option can occur multiple times in order to grant access to more
than one database. Unfortunately, there is no way to grant access to
PostgreSQL databases.

Extra email addresses for the new user can be specified with the C<--extra>
option, followed by an email address within the virtual server. This option
can be given multiple times if you wish.

To create a user who has only FTP access to the domain's website, use the
C<--web> flag. To turn off spam checking for the new user, include
C<--no-check-spam> on the command line. To add the user to additional secondary
Unix groups, the C<--group> flag followed by a group name can be given
multiple times.

For more control over the user's login abilities (FTP, SSH or email only),
use the C<--shell> parameter followed by a full path to a Unix shell, such
as C</bin/false>. Available shells can be displayed using the 
C<list-available-shells> command.

If you only have a pre-encrypted password that you want the new user
to use, the C<--encpass> flag can be used to set it instead of C<--pass>.
However, this will prevent Virtualmin from enabling MySQL access for the user,
as it needs to know the plaintext password to re-hash it for MySQL.

All mail users can have a password recovery address set, used by the forgotten
password feature in Virtualmin. For new users, this can be set with the 
C<--recovery> flag followed by an address.

To add a SSH public key to a user's account, use the C<--ssh-pubkey> flag
followed by the key's content enclosed in quotes, or by the file name containing
the key.

If the given file contains multiple keys, only the key on the first line will be
used, unless C<--ssh-pubkey-id> flag is also given, which will pick the key with
the given ID by matching the key's comment.

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/create-user.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-user.pl must be run as root";
	}
&licence_status();
@OLDARGV = @ARGV;

# Get shells
($nologin_shell, $ftp_shell, $jailed_shell, $shell) =
	&get_common_available_shells();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$username = shift(@ARGV);
		if (!$config{'allow_upper'}) {
			$username = lc($username);
			}
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--passfile") {
		$pass = &read_file_contents(shift(@ARGV));
		$pass =~ s/\r|\n//g;
		}
	elsif ($a eq "--random-pass") {
		$pass = &random_password();
		}
	elsif ($a eq "--encpass") {
		$encpass = shift(@ARGV);
		}
	elsif ($a eq "--ssh-pubkey") {
		$sshpubkey = shift(@ARGV);
		}
	elsif ($a eq "--ssh-pubkey-id") {
		$sshpubkeyid = shift(@ARGV);
		}
	elsif ($a eq "--real" || $a eq "--desc") {
		$real = shift(@ARGV);
		}
	elsif ($a eq "--firstname") {
		$firstname = shift(@ARGV);
		&supports_firstname() || &usage("This system does not support setting first names for users");
		}
	elsif ($a eq "--surname") {
		$surname = shift(@ARGV);
		&supports_firstname() || &usage("This system does not support setting surnames for users");
		}
	elsif ($a eq "--ftp") {
		$shell = $ftp_shell;
		}
	elsif ($a eq "--jailed-ftp") {
		$shell = $jailed_shell;
		}
	elsif ($a eq "--shell") {
		$shell = { 'shell' => shift(@ARGV) };
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
		$quota = 0 if ($quota eq "UNLIMITED");
		}
	elsif ($a eq "--mail-quota") {
		$mquota = shift(@ARGV);
		$mquota = 0 if ($mquota eq "UNLIMITED");
		}
	elsif ($a eq "--mysql") {
		$db = shift(@ARGV);
		push(@dbs, { 'type' => 'mysql', 'name' => $db });
		}
	elsif ($a eq "--db-only") {
		$db_only++;
		}
	elsif ($a eq "--webserver-only") {
		$webserver_only++;
		}
	elsif ($a eq "--webserver-dir") {
		$webdir = shift(@ARGV);
		push(@webdirs, $webdir);
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
	elsif ($a eq "--no-check-spam") {
		$nospam = 1;
		}
	elsif ($a eq "--no-creation-mail") {
		$nocreationmail = 1;
		}
	elsif ($a eq "--recovery") {
		$recovery = shift(@ARGV);
		$recovery =~ /^\S+\@\S+$/ ||
		    &usage("--recovery must be followed by an email address");
		}
	elsif ($a eq "--noappend") {
		$noappend = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$domain || &usage("No domain specified");
$username || &usage("No username specified");
$pass || $encpass || &usage("No password specified");

# Get the initial user
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
&obtain_lock_unix($d);
&obtain_lock_mail($d);
$user = &create_initial_user($d, 0, $web);
$username = &remove_userdom($username, $d);

# Make sure all needed args are set
if (!$user->{'noquota'}) {
	if (&has_home_quotas() && defined($quota)) {
		$quota =~ /^\d+$/ || &usage("Quota must be a number");
		}
	if (&has_mail_quotas() && defined($mquota)) {
		$mquota =~ /^\d+$/ || &usage("Quota must be a number");
		}
	}
$err = &valid_mailbox_name($username);
&usage($err) if ($err);
$real =~ /^[^:]*$/ || usage($text{'user_ereal'});
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
	!$edom->{'alias'} || !$edom->{'aliascopy'} ||
		&usage(&text('user_eextra7', $ed));
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
&build_taken(\%taken, \%utaken);

# Construct user object
if (!$user->{'webowner'}) {
	$user->{'uid'} = &allocate_uid(\%taken);
	}
else {
	$user->{'uid'} = $d->{'uid'};
	}
$user->{'gid'} = $d->{'gid'} || $d->{'ugid'};
$user->{'real'} = $real;
$user->{'firstname'} = $firstname;
$user->{'surname'} = $surname;
$user->{'shell'} = $shell->{'shell'};
if (!$user->{'fixedhome'}) {
	if (defined($home)) {
		# Home was set manually
		if ($home !~ /^\//) {
			$home = "$d->{'home'}/$home";
			}
		$user->{'home'} = $home;
		$user->{'maybecreatehome'} = 1;
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
if ($pass) {
	# Have plain-text password
	$user->{'passmode'} = 3;
	$user->{'plainpass'} = $pass;
	$user->{'pass'} = &encrypt_user_password($user, $pass);
	}
else {
	# Only have encrypted
	$user->{'passmode'} = 2;
	$user->{'pass'} = $encpass;
	}
# SSH public key
my $pubkey;
if ($sshpubkey) {
	my $sshpubkeyfile = -r $sshpubkey ? $sshpubkey : undef;
	if ($sshpubkeyfile) {
		$pubkey = &get_ssh_pubkey_from_file($sshpubkeyfile, $sshpubkeyid);
		}
	else {
		$pubkey = $sshpubkey;
		}
	my $pubkeyerr = &validate_ssh_pubkey($pubkey);
	&usage($pubkeyerr) if ($pubkeyerr);
	}
if ($disable) {
	&set_pass_disable($user, 1);
	}
if (!$user->{'noextra'}) {
	$user->{'extraemail'} = \@extra;
	}
if (($utaken{$username} || $config{'append'}) && !$user->{'noappend'} &&
    !$noappend) {
	$user->{'user'} = &userdom_name($username, $d);
	}
else {
	$user->{'user'} = $username;
	}
if (!$user->{'noprimary'}) {
	if ($noemail) {
		delete($user->{'email'});
		}
	else {
		$user->{'email'} = "$username\@$d->{'dom'}"
		}
	}
if (defined($recovery)) {
	$user->{'recovery'} = $recovery;
	}
if (!$user->{'noquota'}) {
	# Set quotas, if not using the defaults
	$pd = $d->{'parent'} ? &get_domain($d->{'parent'}) : $d;
	if (defined($quota)) {
		$user->{'quota'} = $quota;
		!$quota || !$pd->{'quota'} || $quota <= $pd->{'quota'} ||
			&usage("User's quota cannot be higher than domain's ".
			       "quota of $pd->{'quota'}");
		}
	if (defined($mquota)) {
		$user->{'mquota'} = $mquota;
		!$mquota || !$pd->{'mquota'} || $mquota <= $pd->{'mquota'} ||
			&usage("User's mail quota cannot be higher than ".
			       "domain's mail quota of $pd->{'quota'}");
		}
	}
$user->{'dbs'} = \@dbs if (@dbs);
$user->{'secs'} = \@groups;
$user->{'nospam'} = $nospam;

# Check for a Unix clash
$mclash = &check_clash($username, $d->{'dom'});
if ($utaken{$user->{'user'}} ||
    $user->{'email'} && $mclash ||
    !$user->{'email'} && $mclash == 2) {
	usage($text{'user_eclash'});
	}

# Check for clash within this domain
($clash) = grep { $_->{'user'} eq $username } @users;
$clash && &usage($text{'user_eclash2'});

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

# Validate user
$err = &validate_user($d, $user);
&usage($err) if ($err);

if ($user->{'home'} && !$user->{'nocreatehome'} &&
    (!$user->{'maybecreatehome'} || !-d $user->{'home'})) {
	# Create his homedir
	&create_user_home($user, $d);
	}

if ($db_only) {
	# Create database user only
	my $dbuserclash = &check_extra_user_clash($d, $user->{'user'}, 'db');
        !$dbuserclash || &usage($dbuserclash);
	$user->{'pass'} = $pass;
	# Create database user
        my $err = &create_databases_user($d, $user);
        &usage($err) if ($err);
        # Add user to domain list
	$user->{'extra'} = 1;
        $user->{'type'} = 'db';
        &update_extra_user($d, $user);
	}
elsif ($webserver_only) {
	# Create web-only user
	# Create initial user
        $user->{'extra'} = 1;
        $user->{'type'} = 'web';
        my $userclash = &check_extra_user_clash($d, $user->{'user'}, 'web');
        !$userclash || &usage($userclash);
        # Set initial password
        $user->{'pass'} = $pass;
        $user->{'pass_crypt'} = $encpass, delete($user->{'pass'}) if ($encpass);
        $user->{'pass'} || $user->{'pass_crypt'} || &usage($text{'user_epasswebnotset'});
        &modify_webserver_user($user, undef, $d, { 'virtualmin_htpasswd' => join("\n", @webdirs) });
	}
else {
	# Create the user and virtusers and alias
	&create_user($user, $d);
	if ($pubkey) {
		my $err = &add_domain_user_ssh_pubkey($d, $user, $pubkey);
		&usage($err) if ($err);
		}
	}

# Create an empty mail file, if needed
if ($user->{'email'} && !$user->{'nomailfile'}) {
	&create_mail_file($user, $d);
	}

# Send an email upon creation
if (!$nocreationmail && $user->{'email'}) {
	@erv = &send_user_email($d, $user, undef, 0);
	}

&set_all_null_print();
&run_post_actions();
&release_lock_unix($d);
&release_lock_mail($d);
&virtualmin_api_log(\@OLDARGV, $d, $d->{'hashpass'} ? [ "pass" ] : [ ]);
print "User $user->{'user'} created successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds a new mailbox user to an existing Virtualmin domain.\n";
print "\n";
print "virtualmin create-user --domain domain.name\n";
print "                       --user new-username\n";
print "                       --pass \"password-for-new-user\" |\n";
print "                       --encpass encrypted-password |\n";
print "                       --random-pass |\n";
print "                       --passfile password-file\n";
print "                      [--ssh-pubkey \"key\" | pubkey-file <--ssh-pubkey-id id]\n";
if (&has_home_quotas()) {
	print "                      [--quota quota-in-blocks|\"UNLIMITED\"]\n";
	}
if (&has_mail_quotas()) {
	print "                      [--mail-quota quota-in-blocks|\"UNLIMITED\"]\n";
	}
print "                      [--real real-name-for-new-user]\n";
if (&supports_firstname()) {
	print "                      [--firstname first-name]\n";
	print "                      [--surname surname]\n";
	}
print "                      [--ftp]\n";
if ($jailed_shell) {
	print "                      [--jail-ftp]\n";
	}
print "                      [--shell /path/to/shell]\n";
print "                      [--noemail]\n";
print "                      [--db-only <--mysql db>*]\n";
print "                      [--webserver-only <--webserver-dir path>*]\n";
print "                      [--mysql db]*\n";
print "                      [--extra email.address\@some.domain]\n";
print "                      [--recovery address\@offsite.com]\n";
print "                      [--group name]*\n";
print "                      [--web]\n";
if ($config{'spam'}) {
	print "                      [--no-check-spam]\n";
	}
print "                      [--no-creation-mail]\n";
print "                      [--home directory]\n";
print "                      [--noappend]\n";
exit(1);
}
