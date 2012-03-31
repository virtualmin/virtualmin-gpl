#!/usr/local/bin/perl

=head1 list-features.pl

Lists features available when creating a domain

This command outputs information about Virtualmin features that are available
on this system. It is useful for scripts that are designed to run on many
systems and need to check if some feature is available before creating a 
virtual server or enabling it for a domain.

By default it lists features available for new top-level servers. However,
you can limit it to those that are available for a sub-server with the 
C<--parent> flag, followed by a top-level server name. Similarly, the 
C<--alias> and C<--subdom> flags can be used to show features for an alias
or sub-domain respectively.

Output is in table format by default, but you can switch to a more detailed
and easily parsed list with the C<--multiline> flag. Or to just get a list
of feature codes, use the C<--name-only> parameter.

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
	$0 = "$pwd/list-features.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-features.pl must be run as root";
	}
use POSIX;

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--parent") {
		$parentname = shift(@ARGV);
		}
	elsif ($a eq "--alias") {
		$aliasname = shift(@ARGV);
		}
	elsif ($a eq "--subdom") {
		$subname = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Get the domain objects
if ($parentname) {
	$parentdom = &get_domain_by("dom", $parentname);
	$parentdom ||
	  &usage("Parent virtual server $parentname does not exist");
	}
if ($aliasname) {
	$aliasdom = &get_domain_by("dom", $aliasname);
	$aliasdom ||
	  &usage("Alias target virtual server $aliasname does not exist");
	$parentdom = $aliasdom->{'parent'} ? &get_domain($aliasdom->{'parent'})
					   : $aliasdom;
	}
if ($subname) {
	$subdom = &get_domain_by("dom", $subname);
	$subdom ||
	  &usage("Super-domain virtual server $subname does not exist");
	$parentdom = $subdom->{'parent'} ? &get_domain($subdom->{'parent'})
					 : $subdom;
	}

# Get and show feautures
@feats = &list_available_features($parentdom, $aliasdom, $subdom);
if ($multi) {
	# Several lines each
	foreach $f (@feats) {
		print "$f->{'feature'}\n";
		print "    Description: $f->{'desc'}\n";
		print "    Source: ",($f->{'core'} ? "Core" : "Plugin"),"\n";
		print "    Automatic: ",($f->{'auto'} ? "Yes" : "No"),"\n";
		print "    Enabled: ",($f->{'enabled'} ? "Yes" : "No"),"\n";
		print "    Default: ",($f->{'default'} ? "Yes" : "No"),"\n";
		}
	}
elsif ($nameonly) {
	# Just feature codes
	foreach $f (@feats) {
		print $f->{'feature'},"\n";
		}
	}
else {
	# One per line
	$fmt = "%-20.20s %-50.50s %-8.8s\n";
	printf $fmt, "Code", "Description", "Enabled";
	printf $fmt, ("-" x 20), ("-" x 50), ("-" x 8);
	foreach $f (@feats) {
		printf $fmt, $f->{'feature'}, $f->{'desc'},
			     !$f->{'enabled'} ? "No" :
			     $f->{'auto'} ? "Auto" :
			     $f->{'default'} ? "Yes" : "Off";
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the available features for new virtual servers.\n";
print "\n";
print "virtualmin list-features [--multiline | --name-only]\n";
print "                         [--parent name | --subdom name | --alias name]\n";
exit(1);
}


