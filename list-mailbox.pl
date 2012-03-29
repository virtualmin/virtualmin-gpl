#!/usr/local/bin/perl

=head1 list-mailbox.pl

Dump inbox email for one user

This program is primarily for debugging and testing. It finds the email inbox
for the user in the virtual server identified by the C<--domain> flag whose
login is set with the C<--user> parameter, and outputs the contents in
C<mbox> format. Alternatley you can use the C<--filesonly> flag to just have
it print all the files containing the user's mail (typically just one if
the system using C<mbox> format, or many if C<Maildir> is in use).

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
	$0 = "$pwd/list-mailbox.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-mailbox.pl must be run as root";
	}

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$dname = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$uname = shift(@ARGV);
		}
	elsif ($a eq "--filesonly") {
		$filesonly = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage();
		}
	}

# Parse args and get domain
$dname && $uname || &usage();
$d = &get_domain_by("dom", $dname);
$d || &usage("No domain name $dname found");
@users = &list_domain_users($d, 0, 1, 1, 1);
($user) = grep { $_->{'user'} eq $uname ||
		 &remove_userdom($_->{'user'}, $d) eq $uname } @users;
$user || &usage("Failed to find user $uname in $dname");

# Dump his mail file
&foreign_require("mailboxes", "mailboxes-lib.pl");
($folder) = &mailboxes::list_user_folders($user->{'user'});
if ($filesonly) {
	# Just filenames
	@mails = &mailboxes::mailbox_list_mails(undef, undef, $folder, 1);
	foreach $f (&unique(map { $_->{'file'} || $folder->{'file'} } @mails)) {
		print $f,"\n";
		}
	}
else {
	# Whole contents
	@mails = &mailboxes::mailbox_list_mails(undef, undef, $folder);
	$temp = &transname();
	foreach $m (@mails) {
		&mailboxes::send_mail($m, $temp);
		print &read_file_contents($temp);
		unlink($temp);
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Dumps the mailbox for some user.\n";
print "\n";
print "virtualmin list-mailbox --domain domain.name\n";
print "                        --user name\n";
print "                       [--filesonly]\n";
exit(1);
}

