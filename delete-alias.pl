#!/usr/local/bin/perl
# Deletes a mail alias in some domain

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/delete-alias.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-alias.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--from") {
		$from = shift(@ARGV);
		}
	else {
		&usage();
		}
	}
$from || &usage();

$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$d->{'aliascopy'} && &usage("Aliases cannot be edited in alias domains in copy mode");

# Find the alias
&obtain_lock_mail($d);
@aliases = &list_domain_aliases($d);
$email = $from eq "*" ? "%1\@$domain" : "$from\@$domain";
($virt) = grep { $_->{'from'} eq $email } @aliases;
$virt || &usage("No alias for the email address $email exists");

# Delete it
if (defined(&get_simple_alias)) {
	$simple = &get_simple_alias($d, $virt);
	&delete_simple_autoreply($d, $simple) if ($simple);
	}
&delete_virtuser($virt);
&sync_alias_virtuals($d);
&release_lock_mail($d);
print "Alias for $email deleted successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Deletes a mail alias from a virtual server.\n";
print "\n";
print "usage: delete-alias.pl   --domain domain.name\n";
print "                         --from mailbox\n";
exit(1);
}

