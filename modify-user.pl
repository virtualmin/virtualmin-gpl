#!/usr/local/bin/perl

=head1 modify-user.pl

Change attributes of a mail, FTP or database user

After a user has been created from the command line or web interface, you can
use this program to modify or rename him. The virtual server and user to
change must be specified with the C<--domain> and C<--user> parameters, which are
followed by the server domain name and username respectively.

To change the user's password, use the C<--pass> parameter followed by the new
password. To modify his real name, use the C<--real> option followed by the new
name (which must typically be quoted, in case it contains a space). If you
want to change the user's login name, use the C<--newuser> option, followed by
the new short username (without a suffix).

A user can be temporarily disabled with the C<--disable> option, or re-enabled
with the C<--enable> option. This will not effect his files or password, but will
prevent FTP, IMAP and other logins.

To set the user's disk quota, the C<--quota> option must be used, followed by the
disk quota in 1 kB blocks. An unlimited quota can be set with the parameters
C<--quota UNLIMITED> instead (although of course the user will still be limited
by total server quotas).

A user can be granted or denied FTP access with the C<--enable-ftp> and
C<--disable-ftp> options respectively. Similarly, his primary email address can
be turned on or off with the C<--enable-email> and C<--disable-email> options.

Extra email addresses can be added and removed with the C<--add-email> and
C<--remove-email> options. Both of these must be followed by an address to add or
remove, and both can occur multiple times on the command line.

Access to MySQL databases in the domain can be granted with the 
C<--add-mysql> flag, followed by a database name. Similarly, access can be
removed with the C<--remove-mysql> flag.

To turn off spam checking for the user, the C<--no-check-spam> flag can be
given. This is useful for mailboxes that are supposed to receive all the
spam for some domain. To turn spam filtering back on, use the C<--check-spam>
command-line flag.

The user can also be added to secondary Unix groups with the C<--add-group>
flag, followed by a group name. To remove him from a group, use the
C<--del-group> parameter followed by the group to take him out of.

To add a forwarding email address for this user, use the C<--add-forward>
flag followed by an address or username. Conversely, to remove one use the
C<--del-forward> flag.

To turn off local email delivery for the user, use the C<--no-local> flag.
To turn it back on again, use C<--local>.

To setup an autoreply message, use the C<--autoreply> flag followed by
the message content. To turn off the autoresponder, use the C<--no-autoreply>
parameter.

To control when the autoreply is sent, use the C<--autoreply-start> flag
followed by a date in YYYY-MM-DD format, like 2010-04-01. To set the date on
which is stops being sent, use the C<--autoreply-end> flag. To limit the rate
of replies to the same address, use the C<--autoreply-period> flag followed by
a number in minutes. 

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
	$0 = "$pwd/modify-user.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-user.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Get shells
@ashells = grep { $_->{'mailbox'} && $_->{'avail'} } &list_available_shells();
($nologin_shell, $ftp_shell, $jailed_shell) = &get_common_available_shells();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$username = shift(@ARGV);
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--passfile") {
		$pass = &read_file_contents(shift(@ARGV));
		$pass =~ s/\r|\n//g;
		}
	elsif ($a eq "--real") {
		$real = shift(@ARGV);
		}
	elsif ($a eq "--quota") {
		$quota = shift(@ARGV);
		&has_home_quotas() || &usage("--quota option is not available unless home directory quotas are enabled");
		$quota eq "UNLIMITED" || $quota =~ /^\d+$/ || &usage("Home directory quota must be a number of blocks, or UNLIMITED");
		}
	elsif ($a eq "--mail-quota") {
		$mquota = shift(@ARGV);
		&has_mail_quotas() || &usage("--mail-quota option is not available unless mail directory quotas are enabled");
		$mquota eq "UNLIMITED" || $mquota =~ /^\d+$/ || &usage("Mail directory quota must be a number of blocks, or UNLIMITED");
		}
	elsif ($a eq "--qmail-quota") {
		$qquota = shift(@ARGV);
		&has_server_quotas() || &usage("--qmail-quota option is not available unless supported by the mail server");
		$qquota eq "UNLIMITED" || $qquota =~ /^\d+$/ || &usage("Qmail quota must be a number of blocks, or UNLIMITED");
		}
	elsif ($a eq "--add-mysql") {
		# Adding a MySQL DB to this user's allowed list
		push(@adddbs, { 'type' => 'mysql',
				'name' => shift(@ARGV) });
		}
	elsif ($a eq "--remove-mysql") {
		# Removing a MySQL DB from this user's allowed list
		push(@deldbs, { 'type' => 'mysql',
				'name' => shift(@ARGV) });
		}
	elsif ($a eq "--enable-email") {
		$enable_email = 1;
		}
	elsif ($a eq "--disable-email") {
		$disable_email = 1;
		}
	elsif ($a eq "--add-email") {
		# Adding an extra email address
		push(@addemails, shift(@ARGV));
		}
	elsif ($a eq "--remove-email") {
		# Removing an extra email address
		push(@delemails, shift(@ARGV));
		}
	elsif ($a eq "--newuser") {
		# Changing the username
		$newusername = shift(@ARGV);
		if (!$config{'allow_upper'}) {
			$newusername = lc($newusername);
			}
		$newusername =~ /^[^ \t:]+$/ || &error("Invalid new username");
		}
	elsif ($a eq "--enable-ftp") {
		$shell = $ftp_shell;
		}
	elsif ($a eq "--disable-ftp") {
		$shell = $nologin_shell;
		}
	elsif ($a eq "--jail-ftp") {
		$shell = $jail_shell;
		$shell || &usage("The --jail-ftp option cannot be used without an FTP jail shell specified on the Custom Shells page");
		}
	elsif ($a eq "--shell") {
		$shell = { 'shell' => shift(@ARGV) };
		}
	elsif ($a eq "--add-group") {
		$group = shift(@ARGV);
		push(@addgroups, $group);
		}
	elsif ($a eq "--del-group") {
		$group = shift(@ARGV);
		push(@delgroups, $group);
		}
	elsif ($a eq "--disable") {
		$disable = 1;
		}
	elsif ($a eq "--enable") {
		$enable = 1;
		}
	elsif ($a eq "--update-email" || $a eq "--send-update-email") {
		$remail = 1;
		}
	elsif ($a eq "--no-check-spam") {
		$nospam = 1;
		}
	elsif ($a eq "--check-spam") {
		$nospam = 0;
		}
	elsif ($a eq "--add-forward") {
		push(@addforward, shift(@ARGV));
		}
	elsif ($a eq "--del-forward") {
		push(@delforward, shift(@ARGV));
		}
	elsif ($a eq "--local") {
		$localdelivery = 1;
		}
	elsif ($a eq "--no-local") {
		$localdelivery = 0;
		}
	elsif ($a eq "--autoreply") {
		$autotext = shift(@ARGV);
		$autotext || &usage("Missing parameter for --autoreply");
		}
	elsif ($a eq "--no-autoreply") {
		$autotext = "";
		}
	elsif ($a eq "--autoreply-start") {
		$autostart = &date_to_time(shift(@ARGV));
		}
	elsif ($a eq "--no-autoreply-start") {
		$autostart = '';
		}
	elsif ($a eq "--autoreply-end") {
		$autoend = &date_to_time(shift(@ARGV));
		}
	elsif ($a eq "--no-autoreply-end") {
		$autoend = '';
		}
	elsif ($a eq "--autoreply-period") {
		$autoperiod = shift(@ARGV);
		$autoperiod > 0 && $autoperiod =~ /^\d+$/ ||
			&usage("Autoreply period must be a number in minutes");
		}
	elsif ($a eq "--no-autoreply-period") {
		$autoperiod = '';
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Make sure all needed args are set
$domain && $username || &usage("No domain name or username specified");
$d = &get_domain_by("dom", $domain);
$d || &usage("Virtual server $domain does not exist");
&obtain_lock_mail($d);
&obtain_lock_unix($d);
@users = &list_domain_users($d);
($user) = grep { $_->{'user'} eq $username ||
		 &remove_userdom($_->{'user'}, $d) eq $username } @users;
$user || &usage("No user named $username was found in the server $domain");
$olduser = { %$user };
$shortusername = &remove_userdom($user->{'user'}, $d);
&build_taken(\%taken, \%utaken);
%cangroups = map { $_, 1 } &allowed_secondary_groups($d);
foreach $g (@addgroups) {
	$cangroups{$g} ||
		&usage("Group $g is not allowed for this virtual server");
	}
$disable && $enable && &usage("Only one of the --disable and --enable options can be used");

# Limit what can be done to domain owners
if ($user->{'domainowner'}) {
	$real &&
	  &usage("The --real flag cannot be used when editing a domain owner");
	defined($pass) &&
	  &usage("The --pass and --passfile flags cannot be used when ".
		 "editing a domain owner");
	($quota || $mquota || $qquota) &&
	  &usage("Quotas cannot be changed when editing a domain owner");
	(@adddbs || @deldbs) &&
	  &usage("Databases cannot be changed when editing a domain owner");
	$newusername &&
	  &usage("The username cannot be changed when editing a domain owner");
	$shell &&
	  &usage("The shell cannot be changed when editing a domain owner");
	}

# Make the changes to the user object
&require_useradmin();
if (defined($pass)) {
	$user->{'passmode'} = 3;
	$user->{'plainpass'} = $pass;
	$user->{'pass'} = &encrypt_user_password($user, $pass);
	&set_pass_change($user);
	}
if ($disable) {
	&set_pass_disable($user, 1);
	}
elsif ($enable) {
	&set_pass_disable($user, 0);
	}
if (defined($real)) {
	$real =~ /^[^:]*$/ || &usage("Invalid real name");
	$user->{'real'} = $real;
	}
if (defined($quota) && !$user->{'noquota'}) {
	$user->{'quota'} = $quota eq "UNLIMITED" ? 0 : $quota;
	$quota eq "UNLIMITED" || !$d->{'quota'} || $quota <= $d->{'quota'} ||
		&usage("User's quota cannot be higher than domain's ".
		       "quota of $d->{'quota'}");
	}
if (defined($mquota) && !$user->{'noquota'}) {
	$user->{'mquota'} = $mquota eq "UNLIMITED" ? 0 : $mquota;
	$mquota eq "UNLIMITED" || !$d->{'mquota'} || $mquota <= $d->{'mquota'}||
		&usage("User's mail quota cannot be higher than domain's ".
		       "mail quota of $d->{'quota'}");
	}
if (defined($qquota) && $user->{'mailquota'}) {
	$user->{'qquota'} = $qquota eq "UNLIMITED" ? 0 : $qquota;
	}
@domdbs = &domain_databases($d);
@newdbs = @{$user->{'dbs'}};
foreach $db (@adddbs) {
	($got) = grep { $_->{'type'} eq $db->{'type'} &&
			$_->{'name'} eq $db->{'name'} } @domdbs;
	$got || &usage("The database $db->{'name'} does not exist in this virtual server");
	($clash) = grep { $_->{'type'} eq $db->{'type'} &&
			  $_->{'name'} eq $db->{'name'} } @newdbs;
	$clash && &usage("The user already has access to the database $db->{'name'}");
	push(@newdbs, $db);
	}
foreach $db (@deldbs) {
	($got) = grep { $_->{'type'} eq $db->{'type'} &&
			$_->{'name'} eq $db->{'name'} } @newdbs;
	$got || &usage("The user does not have access to the database $db->{'name'}");
	@newdbs = grep { $_ ne $got } @newdbs;
	}
$user->{'dbs'} = \@newdbs;
if ($enable_email) {
	$user->{'email'} && &usage("The user already has email enabled");
	$user->{'noprimary'} && &usage("Email cannot be enabled for this user");
	$user->{'email'} = $shortusername."\@".$d->{'dom'};
	}
elsif ($disable_email) {
	$user->{'email'} || &usage("The user does not have email enabled");
	$user->{'noprimary'} && &usage("Email cannot be disabled for this user");
	$user->{'email'} = undef;
	}
foreach $e (@addemails) {
	$user->{'noextra'} && &usage("This user cannot have extra email addresses");
	$e = lc($e);
	if ($d && $e =~ /^([^\@ \t]+$)$/) {
		$e = "$e\@$d->{'dom'}";
		}
	if ($e !~ /^(\S*)\@(\S+)$/) {
		&usage("Email address $e is not valid");
		}
	($got) = grep { $_ eq $e } @{$user->{'extraemail'}};
	$got && &usage("Email address $e is already associated with this user");
	$user->{'email'} eq $e && &usage("Email address $e is already the user's primary address");
	push(@{$user->{'extraemail'}}, $e);
	}
foreach $e (@delemails) {
	($got) = grep { $_ eq $e } @{$user->{'extraemail'}};
	$got || &usage("Email address $e does not belong to this user");
	@{$user->{'extraemail'}} = grep { $_ ne $e } @{$user->{'extraemail'}};
	}
if (defined($newusername)) {
	# Generate a new username.. first check for a clash in this domain
	$newusername eq $shortusername &&
		&usage("New username is the same as the old");
	($clash) = grep { &remove_userdom($_->{'user'}, $d) eq $newusername &&
			  $_->{'unix'} == $user->{'unix'} } @users;
	$clash && &usage("A user named $newusername already exists in this ".
			 "virtual server");

	# Append the suffix if needed
	if (($utaken{$newusername} || $config{'append'}) &&
	    !$user->{'noappend'}) {
		$style = &guess_append_style($user->{'user'}, $d);
		$user->{'user'} = &userdom_name($newusername, $d, $style);
		}
	else {
		$user->{'user'} = $newusername;
		}

	# Check if the name is too long
	if ($lerr = &too_long($user->{'user'})) {
		&usage($lerr);
		}

	# Check for a virtuser clash
	if (&check_clash($newusername, $d->{'dom'})) {
		&usage($text{'user_eclash'});
		}

	# Update his home dir, if the old one was automatic
	if (!$user->{'fixedhome'} &&
	    $user->{'home'} eq "$d->{'home'}/$config{'homes_dir'}/$shortusername") {
		$user->{'home'} = "$d->{'home'}/$config{'homes_dir'}/$newusername";
		&rename_file($olduser->{'home'}, $user->{'home'});
		}

	# Update his email address
	if ($user->{'email'} && !$user->{'noprimary'}) {
		$user->{'email'} = $newusername."\@".$d->{'dom'};
		}

	# Set mail file location
	if ($user->{'qmail'}) {
		local $store = &substitute_virtualmin_template(
			$config{'ldap_mailstore'}, $user);
		$user->{'mailstore'} = $store;
		}

	if (!$user->{'nomailfile'}) {
		# Rename his mail file, if needed
		&rename_mail_file($user, $olduser);
		}
	}
if ($shell) {
	$user->{'unix'} ||
		&usage("The shell cannot be changed for non-Unix users");
	$user->{'shell'} = $shell->{'shell'};
	}
if (defined($nospam)) {
	$user->{'nospam'} = $nospam;
	}

# Update secondary groups
@newsecs = &unique(@{$user->{'secs'}}, @addgroups);
%delgroups = map { $_, 1 } @delgroups;
@newsecs = grep { !$delgroups{$_} } @newsecs;
$user->{'secs'} = \@newsecs;

if (!$user->{'noalias'} && ($user->{'email'} || $user->{'noprimary'})) {
	# Apply simple alias changes. If user has no forwarding set yet, assume
	# delivery is local.
	$simple = @{$user->{'to'}} ? &get_simple_alias($d, $user)
				   : { 'tome' => 1 };

	# Update forwarding destinations
	foreach $a (@addforward) {
		push(@{$simple->{'forward'}}, $a);
		}
	foreach $a (@delforward) {
		@{$simple->{'forward'}} = grep { $_ ne $a }
					       @{$simple->{'forward'}};
		}
	@{$simple->{'forward'}} = &unique(@{$simple->{'forward'}});

	# Enable or disable local delivery
	if (defined($localdelivery)) {
		$simple->{'tome'} = $localdelivery;
		}

	# Update autoresponder
	if (defined($autotext)) {
		if ($autotext) {
			$simple->{'from'} ||= $user->{'email'};
			$autotext =~ s/\\n/\n/g;
			$autotext .= "\n" if ($autotext !~ /\n$/);
			$simple->{'autotext'} = $autotext;
			$simple->{'auto'} = 1;
			&set_alias_programs();
			}
		else {
			$simple->{'auto'} = 0;
			}
		}

	# Update autoreply settings
	if ($simple->{'auto'}) {
		$simple->{'autoreply_start'} = $autostart
			if (defined($autostart));
		$simple->{'autoreply_end'} = $autoend
			if (defined($autoend));
		$simple->{'period'} = $autoperiod
			if (defined($autoperiod));
		$simple->{'replies'} ||=
			&convert_autoreply_file($d, "replies-$user->{'user'}")
			if ($simple->{'period'});
		}

	if (@{$user->{'to'}} == 1 && $simple->{'tome'}) {
		# If forwarding is just to the user's # mailbox, then that is
		# like not forwarding at all
		$user->{'to'} = undef;
		}
	&save_simple_alias($d, $user, $simple);
	if (@{$user->{'to'}} == 1 && $simple->{'tome'}) {
		# If forwarding only to local, then that is like no forwarding
		# at all.
		$user->{'to'} = undef;
		}
	if ($autotext || $autostart || $autoend || $autoperiod) {
		&write_simple_autoreply($d, $simple);
		}
	}

# Validate user
$err = &validate_user($d, $user, $olduser);
&usage($err) if ($err);

# Save the user
&modify_user($user, $olduser, $d);

if ($remail) {
	# Email the user his new account details
	&send_user_email($d, $user, undef, 1);
	}

# Create the mail file, if needed
if ($user->{'email'} && !$user->{'nomailfile'}) {
	&create_mail_file($user, $d);
	}

# Call plugin save functions
foreach $f (&list_mail_plugins()) {
	&plugin_call($f, "mailbox_modify", $user, \%old, $d);
	}

# Call other module functions
if ($config{'other_users'}) {
	if ($in{'new'}) {
		&foreign_call($usermodule, "other_modules",
			      "useradmin_create_user", $user);
		}
	else {
		&foreign_call($usermodule, "other_modules",
			      "useradmin_modify_user", $user, $old);
		}
	}

&set_all_null_print();
&run_post_actions();
&release_lock_mail($d);
&release_lock_unix($d);
&virtualmin_api_log(\@OLDARGV, $d, $d->{'hashpass'} ? [ "pass" ] : [ ]);
print "User $user->{'user'} updated successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Modifies a mail, FTP or database user in a Virtualmin domain.\n";
print "\n";
print "virtualmin modify-user --domain domain.name\n";
print "                       --user username\n";
print "                      [--pass new-password | --passfile password-file]\n";
print "                      [--disable | --enable]\n";
print "                      [--real real-name]\n";
if (&has_home_quotas()) {
	print "                      [--quota quota-in-blocks]\n";
	}
if (&has_mail_quotas()) {
	print "                      [--mail-quota quota-in-blocks]\n";
	}
if (&has_server_quotas()) {
	print "                      [--qmail-quota quota-in-bytes]\n";
	}
if ($config{'mysql'}) {
	print "                      [--add-mysql database]\n";
	print "                      [--remove-mysql database]\n";
	}
if ($config{'mail'}) {
	print "                      [--enable-email]\n";
	print "                      [--disable-email]\n";
	print "                      [--add-email address]\n";
	print "                      [--remove-email address]\n";
	}
print "                      [--newuser new-username]\n";
print "                      [--enable-ftp]\n";
print "                      [--disable-ftp]\n";
if ($config{'jail_shell'}) {
	print "                      [--jail-ftp]\n";
	}
print "                      [--add-group group]*\n";
print "                      [--del-group group]*\n";
print "                      [--send-update-email]\n";
if ($config{'spam'}) {
	print "                      [--no-check-spam | --check-spam]\n";
	}
print "                      [--add-forward address]*\n";
print "                      [--del-forward address]*\n";
print "                      [--local | --no-local]\n";
print "                      [--autoreply \"messsage\" | --no-autoreply]\n";
print "                      [--autoreply-start time | --no-autoreply-start]\n";
print "                      [--autoreply-end time | --no-autoreply-end]\n";
print "                      [--autoreply-period secs | --no-autoreply-period]\n";
exit(1);
}

