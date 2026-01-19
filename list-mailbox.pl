#!/usr/local/bin/perl

=head1 list-mailbox.pl

Dump inbox email for one user

This program is primarily for debugging and testing. It finds the email inbox
for the user in the virtual server identified by the C<--domain> flag whose
login is set with the C<--user> parameter, and outputs the contents in
C<mbox> format. Alternately you can use the C<--filesonly> flag to just have
it print all the files containing the user's mail (typically just one if
the system using C<mbox> format, or many if C<Maildir> is in use).

By default the user's inbox is listed, however you can select any folder
owned by the user with the C<--folder> flag followed by either a path or
a unique folder ID.

By default all messages in the folder will be listed, but you can limit
output to the oldest N messages with the flag C<--first N>. Or the most
recent N messages with C<--last N>.

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
&parse_common_cli_flags(\@ARGV);
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
	elsif ($a eq "--folder") {
		$folderid = shift(@ARGV);
		}
	elsif ($a eq "--first") {
		$first = shift(@ARGV);
		$first =~ /^[1-9][0-9]*$/ || &usage("--first must be followed by a number ".
						    "greater than zero");
		}
	elsif ($a eq "--last") {
		$last = shift(@ARGV);
		$last =~ /^[1-9][0-9]*$/ || &usage("--last must be followed by a number ".
						   "greater than zero");
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$convert_format && &usage("XML or JSON conversion is not supported");
$first && $last && &usage("Only one of --first and --last can be given");

# Parse args and get domain
$dname || &usage("No domain specified");
$uname || &usage("No username specified");
$d = &get_domain_by("dom", $dname);
$d || &usage("No domain name $dname found");
@users = &list_domain_users($d, 0, 1, 1, 1);
($user) = grep { $_->{'user'} eq $uname ||
		 &remove_userdom($_->{'user'}, $d) eq $uname } @users;
$user || &usage("Failed to find user $uname in $dname");

# Dump his mail file
&foreign_require("mailboxes");
@folders = &mailboxes::list_user_folders($user->{'user'});
@folders || &usage("User has no mail folders!");
if ($folderid) {
	($folder) = grep { $_->{'file'} eq $folderid ||
			   &mailboxes::folder_name($_) eq $folderid } @folders;
	$folder || &usage("No folder with ID $folderid found");
	}
else {
	$folder = $folders[0];
	}
if ($filesonly) {
	# Just filenames
	@mails = &mailboxes::mailbox_list_mails(undef, undef, $folder, 1);
	%done = ( );
	for(my $i=0; $i<@mails; $i++) {
                my $m = $mails[$i];
                next if ($first && $i > $first);
                next if ($last && $i < @mails - $last);
		my $f = $m->{'file'} || $folder->{'file'};
		print $f,"\n" if (!$done{$f}++);
		}
	}
else {
	# Whole contents
	@mails = &mailboxes::mailbox_list_mails(undef, undef, $folder);
	$temp = &transname();
	for(my $i=0; $i<@mails; $i++) {
		my $m = $mails[$i];
		next if ($first && $i > $first);
		next if ($last && $i < @mails - $last);
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
print "                       [--folder name|path]\n";
print "                       [--filesonly]\n";
print "                       [--first N | --last N]\n";
exit(1);
}

