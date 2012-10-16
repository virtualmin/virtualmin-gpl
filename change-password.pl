#!/usr/local/bin/perl

=head1 change-password.pl

Changes the password of some Virtualmin user.

Designed to be called from Usermin's Change Passwords module. If you want to
change a password from the command line, use the C<modify-domain> command
instead.

=cut

$no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*)\/[^\/]+$/) {
	chdir($pwd = $1);
	}
else {
	chop($pwd = `pwd`);
	}
$0 = "$pwd/change-password.pl";
require './virtual-server-lib.pl';
$< == 0 || die "change-password.pl must be run as root";
&require_useradmin();

# Read inputs
$| = 1;
&usage() if ($ARGV[0] eq "--help");
if ($ARGV[0]) {
	$username = $ARGV[0];
	}
else {
	print "Username: ";
	chop($username = <STDIN>);
	}
print "Old password: ";
chop($oldpass = <STDIN>);
print "New password: ";
chop($newpass = <STDIN>);
if (!$username) {
	&error_exit("No username given");
	}
$username = lc($username);
sleep(5);		# To prevent brute force attacks

# Find the user
$d = &get_user_domain($username);
$d || &error_exit("Not a Virtualmin user");
@users = &list_domain_users($d);
($user) = grep { $_->{'user'} eq $username ||
		 &replace_atsign($_->{'user'}) eq $username } @users;
$user || &error_exit("Not a Virtualmin user in $d->{'dom'}");
$olduser = { %$user };

if ($user->{'domainowner'}) {
	# This is the domain owner, so changing his password means updating
	# all features
	if ($d->{'pass'}) {
		$d->{'pass'} eq $oldpass || &error_exit("Wrong password");
		}
	else {
		&useradmin::validate_password($oldpass, $user->{'pass'}) ||
			&error_exit("Wrong password");
		}
	&set_all_null_print();
	foreach my $d (&get_domain_by("user", $username)) {
		$oldd = { %$d };
		$d->{'pass'} = $newpass;
		$d->{'pass_set'} = 1;
		&generate_domain_password_hashes($d, 0);
		if ($d->{'disabled'}) {
			# Clear any saved passwords, as they should
			# be reset at this point
			$d->{'disabled_oldpass'} = $_[0]->{'pass'};
			$d->{'disabled_mysqlpass'} = undef;
			$d->{'disabled_postgrespass'} = undef;
			}
		# Update all features
		foreach my $f (@features) {
			if ($config{$f} && $d->{$f}) {
				local $mfunc = "modify_".$f;
				&$mfunc($d, $oldd);
				}
			}
		# Update all plugins
		foreach my $f (&list_feature_plugins()) {
			if ($d->{$f}) {
				&plugin_call($f, "feature_modify", $d, $oldd);
				}
			}
		&save_domain($d);
		}
	&run_post_actions();
	}
else {
	# Can just change the user
	$olduser = { %$user };
	if (defined($user->{'plainpass'})) {
		$user->{'plainpass'} eq $oldpass ||
			&error_exit("Wrong password");
		}
	elsif ($user->{'pass'}) {
		&require_useradmin();
		&useradmin::validate_password($oldpass, $user->{'pass'}) ||
			&error_exit("Wrong password");
		}
	$user->{'passmode'} = 3;
	$user->{'plainpass'} = $newpass;
	$user->{'pass'} = &encrypt_user_password($user, $newpass);
	&set_pass_change($user);
	&modify_user($user, $olduser, $d);

	# Call plugin save functions
	foreach $f (&list_mail_plugins()) {
		&plugin_call($f, "mailbox_modify", $user, $olduser, $d);
		}
	}

print "Password changed for $username in $d->{'dom'}\n";
exit(0);

sub error_exit
{
print STDERR @_,"\n";
exit(1);
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes the password of a Virtualmin user\n";
print "\n";
print "virtualmin change-password [username]\n";
exit(1);
}

