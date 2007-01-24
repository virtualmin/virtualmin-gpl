#!/usr/local/bin/perl
# Changes the password of some Virtualmin user. Designed to be called
# setuid, by non-root users.

#open(DEBUG, ">/tmp/change-password.debug");
open(DEBUG, ">/dev/null");
#close(STDERR);
#open(STDERR, ">&DEBUG");
select(DEBUG); $| = 1; select(STDOUT);

print DEBUG "Running as $<\n";
$no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
print DEBUG "Before setting \$0 (from $0)\n";
$0 = "$pwd/change-password.pl";
print DEBUG "Before require\n";
eval "require './virtual-server-lib.pl';";
print DEBUG $@;
print DEBUG "After require\n";
$< == 0 || die "change-password.pl must be run as root";
print DEBUG "Password preliminary checks\n";

# Read inputs
$| = 1;
print "Username: ";
chop($username = <STDIN>);
print "Old password: ";
chop($oldpass = <STDIN>);
print "New password: ";
chop($newpass = <STDIN>);
$username || die "No username given";
print DEBUG "username=$username oldpass=$oldpass newpass=$newpass\n";
sleep(5);		# To prevent brute force attacks

# Find the user
$d = &get_user_domain($username);
$d || die "Not a Virtualmin user";
@users = &list_domain_users($d);
($user) = grep { $_->{'user'} eq $username } @users;
$user || die "Not a Virtualmin user in $d->{'dom'}";
$olduser = { %$user };

if ($user->{'domainowner'}) {
	# This is the domain owner, so changing his password means updating
	# all features
	$d->{'pass'} eq $oldpass || die "Wrong password";
	&set_all_null_print();
	foreach my $d (&get_domain_by("user", $username)) {
		$oldd = { %$d };
		$d->{'pass'} = $newpass;
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
		foreach my $f (@feature_plugins) {
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
	if (defined($user->{'plainpass'})) {
		$user->{'plainpass'} eq $oldpass || die "Wrong password";
		}
	$user->{'passmode'} = 3;
	$user->{'plainpass'} = $newpass;
	$user->{'pass'} = &encrypt_user_password($user, $newpass);
	&modify_user($user, $olduser, $d);
	}

print "Password changed for $username in $d->{'dom'}\n";
exit(0);

