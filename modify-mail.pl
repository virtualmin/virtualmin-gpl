#!/usr/local/bin/perl
# Change mail-related settings for some domains

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/modify-mail.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-mail.pl must be run as root";
	}
@OLDARGV = @ARGV;
$config{'mail'} || &usage("Email is not enabled for Virtualmin");
&require_mail();

&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--bcc") {
		$bcc = shift(@ARGV);
		}
	elsif ($a eq "--no-bcc") {
		$bcc = "";
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--alias-copy") {
		$aliascopy = 1;
		$supports_aliascopy ||
			&usage("Your mail server does not support changing the alias mode");
		}
	elsif ($a eq "--alias-catchall") {
		$aliascopy = 0;
		}
	else {
		&usage();
		}
	}
@dnames || $all_doms || @users || usage();
defined($bcc) || defined($aliascopy) || &usage("Nothing to do");

# Get domains to update
if ($all_doms == 1) {
	@doms = grep { $_->{'mail'} } &list_domains();
	}
else {
	# Get domains by name and user
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}
@doms = grep { $_->{'mail'} } @doms;
@doms || &usage("None of the selected domains have email enabled");

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	&$indent_print();
	$oldd = { %$d };

	# Turn BCCing on or off
	$currbcc = &get_domain_sender_bcc($d);
	if (defined($bcc)) {
		if ($bcc) {
			# Change or enable
			&$first_print("BCCing all email to $bcc ..");
			&save_domain_sender_bcc($d, $bcc);
			&$second_print(".. done");
			}
		elsif (!$bcc && $currbcc) {
			# Turn off
			&$first_print("Turning off BCCing ..");
			&save_domain_sender_bcc($d, undef);
			&$second_print(".. done");
			}
		}

	# Change alias mode
	if ($d->{'alias'} && defined($aliascopy)) {
		my $aliasdom = &get_domain($d->{'alias'});
		if ($d->{'aliascopy'} && !$aliascopy) {
			# Switch to catchall
			&$first_print("Switching to catchall for ".
				      "server $d->{'dom'} ..");
			&delete_alias_virtuals($d);
			&create_virtuser({ 'from' => '@'.$d->{'dom'},
				   'to' => [ '%1@'.$aliasdom->{'dom'} ] });
			&$second_print(".. done");
			}
		elsif (!$d->{'aliascopy'} && $aliascopy) {
			# Switch to copy mode
			&$first_print("Switching to alias copy for ".
				      "server $d->{'dom'} ..");
			&copy_alias_virtuals($d, $aliasdom);
			&$second_print(".. done");
			}

		# Save new domain details
		$d->{'aliascopy'} = $aliascopy;
		}

	&save_domain($d);

	&$outdent_print();
	&$second_print(".. done");
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes email-related settings for one or more domains.\n";
print "\n";
print "usage: modify-mail.pl [--domain name]* |\n";
print "                      [--user name] |\n";
print "                      [--all-domains]\n";
print "                      [--bcc user\@domain] | [--no-bcc]\n";
print "                      [--alias-copy] | [--alias-catchall]\n";
exit(1);
}

