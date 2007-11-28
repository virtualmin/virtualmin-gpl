#!/usr/local/bin/perl
# Change the mail alias mode for a domain

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/modify-aliascopy.pl";
require './virtual-server-lib.pl';
$< == 0 || die "modify-aliascopy.pl must be run as root";
&require_mail();

# Parse command-line args
&set_all_text_print();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--alias-copy") {
		$aliascopy = 1;
		}
	elsif ($a eq "--alias-catchall") {
		$aliascopy = 0;
		}
	else {
		&usage();
		}
	}
@dnames || $all_doms || @users || usage();
defined($aliascopy) || &usage("Missing --alias-copy or --alias-catchall");

# Get domains to update
if ($all_doms) {
	@doms = &list_domains();
	}
else {
	# Get domains by name and user
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}
@doms = grep { $_->{'alias'} && $_->{'mail'} } @doms;
@doms || &usage("None of the selected domains are aliases with email");
$supports_aliascopy || &usage("Your mail server does not support changing the alias mode");

# Do it for all domains
foreach $d (@doms) {
	my $aliasdom = &get_domain($d->{'alias'});
	if ($d->{'aliascopy'} && !$aliascopy) {
		# Switch to catchall
		&$first_print("Switching to catchall for server $d->{'dom'} ..");
		&create_alias_catchall($d, $aliasdom);
		&$second_print(".. done");
		}
	elsif (!$d->{'aliascopy'} && $aliascopy) {
		# Switch to copy mode
		&$first_print("Switching to alias copy for server $d->{'dom'} ..");
		&copy_alias_virtuals($d, $aliasdom);
		&$second_print(".. done");
		}

	# Save new domain details
	$d->{'aliascopy'} = $aliascopy;
	&save_domain($d);
	}

&run_post_actions();

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes the email alias mode for alias virtual servers.\n";
print "\n";
print "usage: modify-aliascopy.pl [--domain name] |\n";
print "                           [--user name] |\n";
print "                           [--all-domains]\n";
print "                           --alias-copy | --alias-catchall\n";
exit(1);
}

