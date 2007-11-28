#!/usr/local/bin/perl
# Adds a mail alias to some domain, with simple parameters

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/create-simple-alias.pl";
require './virtual-server-lib.pl';
$< == 0 || die "create-simple-alias.pl must be run as root";

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
	elsif ($a eq "--forward") {
		$forward = shift(@ARGV);
		$forward =~ /^\S+\@\S+$/ ||
			&usage("Invalid email address for --forward");
		push(@forward, $forward);
		}
	elsif ($a eq "--bounce") {
		$bounce = 1;
		}
	elsif ($a eq "--local") {
		$local = shift(@ARGV);
		defined(getpwnam($local)) ||
			&usage("Missing or invalid local user for --local");
		}
	elsif ($a eq "--autoreply") {
		$autotext = shift(@ARGV);
		$autotext || &usage("Missing parameter for --autoreply");
		}
	elsif ($a eq "--autoreply-period") {
		$period = shift(@ARGV);
		$period =~ /^\d+$/ || &usage("Invalid parameter for --period");
		}
	elsif ($a eq "--autoreply-from") {
		$autofrom = shift(@ARGV);
		$autofrom =~ /^\S+\@\S+$/ ||
			&usage("Invalid email address for --autoreply-from");
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
$bounce || $local || @forward || $autotext || &usage();

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

# Create the simple object
$simple = { };
$simple->{'bounce'} = 1 if ($bounce);
$simple->{'local'} = $local if ($local);
$simple->{'forward'} = \@forward;
if ($autotext) {
	$simple->{'auto'} = 1;
	$simple->{'autotext'} = $autotext;
	if ($period) {
		$simple->{'replies'} =
			&convert_autoreply_file($d, "replies-$from");
		$simple->{'period'} = $period;
		}
	if ($autofrom) {
		$simple->{'from'} = $autofrom;
		}
	}

# Create it
$virt = { 'from' => $email,
	  'cmt' => $cmt };
&save_simple_alias($d, $virt, $simple);
&create_virtuser($virt);
&switch_to_domain_user($d);
&write_simple_autoreply($d, $simple);
print "Alias for $email created successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Adds a simple mail alias to a virtual server.\n";
print "\n";
print "usage: create-simple-alias.pl   --domain domain.name\n";
print "                                --from mailbox\n";
print "                                [--forward user\@domain]*\n";
print "                                [--local local-user]\n";
print "                                [--bounce]\n";
print "                                [--autoreply \"some message\"]\n";
print "                                [--autoreply-period hours]\n";
print "                                [--autoreply-from user\@domain]\n";
if ($can_alias_comments) {
	print "                                [--desc \"Comment text\"]\n";
	}
exit(1);
}

