#!/usr/local/bin/perl

=head1 modify-spam.pl

Change spam filtering and delivery settings for a virtual server

This command can be used to change the location than email tagged as spam or
virus-laden is delivered to for one or more virtual servers. The servers to act
on can be either specified with the C<--domain> parameter, or all domains with
spam filtering enabled can be selected with C<--all-domains>.

The following parameters control what happens to messages identified as spam :

C<--spam-delete> Delete all spam mail.
C<--spam-deliver> Deliver to user's mailbox normally.
C<--spam-mailfile> Write to user's C<~/mail/spam> file in mbox format.
C<--spam-maildir> Write to user's C<~/Maildir/.spam> file in Maildir format.
C<--spam-file> Write to the file following this parameter, which must be relative to the user's home directory.
C<--spam-email> Forward to the email address following this parameter.
C<--spam-dest> Write to the absolute file following the parameter.

A similar set of options exist for virus filtering, but starting with C<--virus>
instead of C<--spam>.

Virtualmin has the ability to delete spam from the spam folders of all users
in a domain once it passes some threshold, such as age or size. You can
enable this with the C<--spamclear-days> parameter followed by the maximum
age in days, or C<--spamclear-size> followed by a size in bytes. Or to turn
off spam deletion, use the C<--spamclear-none> parameter.

Similarly you can enable automatic deletion from trash folders with the
C<--trashclear-days> parameter followed by the maximum age in days, or
C<--trashclear-size> followed by a size in bytes. Or to turn off trash
deletion, use the C<--trashclear-none> parameter.

SpamAssassin gives each message it scans a numeric score, and typically anything
above 5 is considered spam and placed in a separate user folder. However, you
can choose to simply delete all incoming spam with a score above some higher
threshold (such as 10) using the C<--spam-delete-level> parameter, which must
be followed by a number. To turn this behaviour off again, use the 
C<--spam-no-delete-level> flag.

To enable the spamtrap and hamtrap aliases for the selected virtual servers,
you can use the C<--spamtrap> command-line flag. Similarly, to remove them
use the C<--no-spamtrap> flag. When enabled, users will be able to forward
spam to spamtrap@theirdomain.com for adding to the domain's blacklist.

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
	$0 = "$pwd/modify-spam.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-spam.pl must be run as root";
	}
@OLDARGV = @ARGV;
$config{'spam'} || &usage("Spam filtering is not enabled for Virtualmin");
&set_all_text_print();

# Parse command-line args
$spamlevel = undef;
$auto = { };
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a =~ /^--(spam|virus)-delete$/) {
		$mode{$1} = 0;
		}
	elsif ($a =~ /^--(spam)-deliver$/) {
		$mode{$1} = 5;
		}
	elsif ($a =~ /^--(spam|virus)-(normal|mailfile)$/) {
		$m = $1;
		$mode{$m} = 4;
		if (@ARGV && $ARGV[0] !~ /^-/) {
			$dest{$m} = shift(@ARGV);
			}
		}
	elsif ($a =~ /^--(spam|virus)-maildir$/) {
		$m = $1;
		$mode{$m} = 6;
		if (@ARGV && $ARGV[0] !~ /^-/) {
			$dest{$m} = shift(@ARGV);
			}
		}
	elsif ($a =~ /^--(spam|virus)-file$/) {
		$mode{$1} = 1;
		$dest{$1} = shift(@ARGV);
		$dest{$1} =~ /\S/ && $dest{$1} !~ /\.\./ &&
		    $dest{$1} !~ /^\// ||
			&usage("The $a option must be followed by a relative filename");
		}
	elsif ($a =~ /^--(spam|virus)-email$/) {
		$mode{$1} = 2;
		$dest{$1} = shift(@ARGV);
		$dest{$1} =~ /\@/ || &usage("The $a option must be followed by an email address");
		}
	elsif ($a =~ /^--(spam|virus)-dest$/) {
		$mode{$1} = 3;
		$dest{$1} = shift(@ARGV);
		$dest{$1} =~ /\S/ || &usage("The $a option must be followed by a mail file path");
		}
	elsif ($a eq "--spam-whitelist") {
		$spam_white = 1;
		}
	elsif ($a eq "--no-spam-whitelist") {
		$spam_white = 0;
		}
	elsif ($a =~ /^--use-(spamc|spamassassin)$/) {
		$spam_client = $1;
		}
	elsif ($a eq "--spamclear-none") {
		$auto->{'days'} = $auto->{'size'} = undef;
		}
	elsif ($a eq "--spamclear-days") {
		$auto->{'days'} = shift(@ARGV);
		$auto->{'days'} =~ /^\d+$/ ||
		  &usage("The $a option must be followed by a number of days");
		$auto->{'size'} = undef;
		}
	elsif ($a eq "--spamclear-size") {
		$auto->{'size'} = shift(@ARGV);
		$auto->{'size'} =~ /^\d+$/ ||
		  &usage("The $a option must be followed by a size in bytes");
		$auto->{'days'} = undef;
		}
	elsif ($a eq "--trashclear-none") {
		$auto->{'trashdays'} = $auto->{'trashsize'} = undef;
		}
	elsif ($a eq "--trashclear-days") {
		$auto->{'trashdays'} = shift(@ARGV);
		$auto->{'trashdays'} =~ /^\d+$/ ||
		  &usage("The $a option must be followed by a number of days");
		$auto->{'trashsize'} = undef;
		}
	elsif ($a eq "--trashclear-size") {
		$auto->{'trashsize'} = shift(@ARGV);
		$auto->{'trashsize'} =~ /^\d+$/ ||
		  &usage("The $a option must be followed by a size in bytes");
		$auto->{'trashdays'} = undef;
		}
	elsif ($a eq "--spam-delete-level") {
		$spamlevel = shift(@ARGV);
		$spamlevel =~ /^[1-9]\d*$/ ||
		    &usage("--spam-delete-level must be followed by a number");
		}
	elsif ($a eq "--spam-no-delete-level") {
		$spamlevel = 0;
		}
	elsif ($a =~ /^--use-(clamscan|clamdscan|clamd-stream-client|clamdscan-remote)$/) {
		$virus_scanner = $1;
		}
	elsif ($a eq "--spamtrap") {
		$spamtrap = 1;
		}
	elsif ($a eq "--no-spamtrap") {
		$spamtrap = 0;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
@dnames || $all_doms || usage("No domains specified");
defined($mode{'spam'}) || defined($mode{'virus'}) || $spam_client ||
    $virus_scanner || defined($auto) || defined($spamlevel) ||
    defined($spamtrap) || &usage("Nothing to do");

# Get domains to update
if ($all_doms) {
	@doms = grep { $_->{'spam'} } &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		$d->{'spam'} || &usage("Virtual server $n does not have spam filtering enabled");
		push(@doms, $d);
		}
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	&obtain_lock_spam($d);
	&obtain_lock_cron($d);
	&obtain_lock_mail($d);
	&$indent_print();

	if ($config{'spam'} && $d->{'spam'} &&
	    (defined($mode{'spam'}) || defined($spamlevel))) {
		&save_domain_spam_delivery($d, $mode{'spam'}, $dest{'spam'},
					   $spamlevel, undef);
		}
	if ($config{'virus'} && $d->{'virus'} && defined($mode{'virus'})) {
		&save_domain_virus_delivery($d, $mode{'virus'}, $dest{'virus'});
		}
	if ($config{'spam'} && $d->{'spam'} && $spam_client) {
		&save_domain_spam_client($d, $spam_client);
		&modify_webmin($d, $d);
		}
	if (defined($spam_white)) {
		if (&get_domain_spam_client($d) eq "spamc") {
			&$second_print(".. whitelist cannot be configured ".
				       "spamc is in use");
			}
		else {
			$d->{'spam_white'} = $spam_white;
			&update_spam_whitelist($d);
			&save_domain($d);
			}
		}
	if (keys %$auto) {
		my $oldauto = &get_domain_spam_autoclear($d);
		foreach my $k (keys %$auto) {
			$oldauto->{$k} = $auto->{$k};
			}
		&save_domain_spam_autoclear($d, $oldauto);
		}
	if (defined($virus_scanner)) {
		&save_domain_virus_scanner($d, $virus_scanner);
		}
	if (defined($spamtrap)) {
		$st = &get_spamtrap_aliases($d);
		if ($st < 0) {
			&$first_print("Spam trap aliases already exist");
			}
		elsif ($st && !$spamtrap) {
			&$first_print("Removing spam trap aliases ..");
			$err = &delete_spamtrap_aliases($d);
			&$second_print($err ? ".. failed : $err" : ".. done");
			}
		elsif (!$st && $spamtrap) {
			&$first_print("Adding spam trap aliases ..");
			$err = &setup_spamtrap_aliases($d);
			&$second_print($err ? ".. failed : $err" : ".. done");
			}
		}

	&$outdent_print();
	&release_lock_mail($d);
	&release_lock_spam($d);
	&release_lock_cron($d);
	&$second_print(".. done");
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes the spam and virus delivery modes for one or more domains.\n";
print "\n";
print "virtualmin modify-spam --domain name | --all-domains\n";
print "                      [--spam-delete | --spam-deliver |\n";
print "                       --spam-mailfile [folder] |\n";
print"                        --spam-file file-under-home |\n";
print "                       --spam-email address | --spam-dest file |\n";
print "                       --spam-maildir [folder] ]\n";
print "                      [--spam-delete-level score | --spam-no-delete-level]\n";
print "                      [--virus-delete |\n";
print "                       --virus-mailfile [folder] |\n";
print "                       --virus-file file-under-home |\n";
print "                       --virus-email address | --virus-dest file\n";
print "                       --virus-maildir [folder] ]\n";
print "                      [--spam-whitelist | --no-spam-whitelist]\n";
print "                      [--use-spamassassin | --use-spamc]\n";
print "                      [--spamclear-none |\n";
print "                       --spamclear-days days\n";
print "                       --spamclear-size bytes]\n";
print "                      [--trashclear-none |\n";
print "                       --trashclear-days days\n";
print "                       --trashclear-size bytes]\n";
print "                      [--use-clamscan | --use-clamdscan |\n";
print "                       --use-clamd-stream-client | --use-clamdscan-remote]\n";
print "                      [--spamtrap | --no-spamtrap]\n";
print "\n";
print "Warning - modifying the SpamAssassin or virus scanning client for\n";
print "individual domains is deprecated.\n";
exit(1);
}

