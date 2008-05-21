#!/usr/local/bin/perl
# Disable logging via program 

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/disable-writelogs.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "disable-writelogs.pl must be run as root";
	}
@OLDARGV = @ARGV;

$first_print = \&first_text_print;
$second_print = \&second_text_print;
$indent_print = \&indent_text_print;
$outdent_print = \&outdent_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	}
@dnames || $all_doms || usage();

# Get domains to update
if ($all_doms) {
	@doms = grep { $_->{'web'} && &get_writelogs_status($_) }
		     &list_domains();
	}
else {
	foreach $n (@dnames) {
		$d = &get_domain_by("dom", $n);
		$d || &usage("Domain $n does not exist");
		$d->{'web'} || &usage("Domain $n does not have a website");
		&get_writelogs_status($d) || &usage("Domain $n is not logging via a program");
		push(@doms, $d);
		}
	}

# Lock them all
foreach $d (@doms) {
	&obtain_lock_web($d);
	}

# Do it for all domains
foreach $d (@doms) {
	&$first_print("Updating server $d->{'dom'} ..");
	&$indent_print();

	&disable_writelogs($d);

	&$outdent_print();
	&$second_print(".. done");
	}

foreach $d (@doms) {
	&release_lock_web($d);
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Disables logging via program for one or more domains specified on the\n";
print "command line.\n";
print "\n";
print "usage: disable-writelogs.pl [--domain name] | [--all-domains]\n";
exit(1);
}

