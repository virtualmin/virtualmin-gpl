#!/usr/local/bin/perl
# Adds a mail alias to some domain

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/create-alias.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-alias.pl must be run as root";
	}

# Parse command-line args
&require_mail();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--from") {
		$from = shift(@ARGV);
		}
	elsif ($a eq "--to") {
		push(@to, shift(@ARGV));
		}
	elsif ($a eq "--desc") {
		$can_alias_comments ||
		  usage("Your mail server does not support alias descriptions");
		$cmt = shift(@ARGV);
		}
	else {
		&usage();
		}
	}
$from || &usage();
@to || &usage();

$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$d->{'mail'} || usage("Virtual server $domain does not have email enabled");
$from =~ /\@/ && &usage("No domain name is needed in the --from parameter");
$d->{'aliascopy'} && &usage("Aliases cannot be edited in alias domains in copy mode");

# Check for clash
@aliases = &list_domain_aliases($d);
$email = $from eq "*" ? "%1\@$domain" : "$from\@$domain";
($clash) = grep { $_->{'from'} eq $email } @aliases;
$clash && &usage("An alias for the same email address already exists");

# Create it
$virt = { 'from' => $email,
	  'to' => \@to,
	  'cmt' => $cmt };
&create_virtuser($virt);
&sync_alias_virtuals($d);
print "Alias for $email created successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds a mail alias to a virtual server.\n";
print "\n";
print "usage: create-alias.pl   --domain domain.name\n";
print "                         --from mailbox\n";
print "                         --to address [--to address ...]\n";
if ($can_alias_comments) {
	print "                         [--desc \"Comment text\"]\n";
	}
exit(1);
}

