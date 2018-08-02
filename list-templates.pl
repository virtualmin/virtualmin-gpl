#!/usr/local/bin/perl

=head1 list-templates.pl

List available templates for new domains

The command simply outputs a list of available templates for use when
creating new virtual servers. For each the ID number and description
are diplayed.

To just display the template names, you can give the C<--name-only> parameter.
This is useful when iterating through them in other scripts.

By default, deleted templates are not incluced in the list unless you
add the C<--deleted> flag.

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
	$0 = "$pwd/list-templates.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-templates.pl must be run as root";
	}

# Parse command-line args
$owner = 1;
$deleted = 0;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	elsif ($a eq "--deleted") {
		$deleted = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Get templates to show
@tmpls = &list_templates();
if (!$deleted) {
	@tmpls = grep { !$_->{'deleted'} } @tmpls;
	}

if ($nameonly) {
	# Just template IDs
	foreach $tmpl (@tmpls) {
		print $tmpl->{'name'},"\n";
		}
	}
elsif ($multiline) {
	# Multiline format with some details
	foreach $tmpl (@tmpls) {
		print $tmpl->{'id'},"\n";
		print "    Name: ",$tmpl->{'name'},"\n";
		foreach $w ('web', 'dns', 'ftp', 'logrotate', 'mail_on') {
			($sw = $w) =~ s/_on$//;
			print "    Custom ${sw}: ",
			      ($tmpl->{$w} eq "none" ? "None" :
			       $tmpl->{$w} eq "" ? "Default" : "Custom"),"\n";
			}
		}
	}
else {
	# More details
	$fmt = "%-18.18s %-60.60s\n";
	printf $fmt, "ID", "Description";
	printf $fmt, ("-" x 18), ("-" x 60);
	foreach $tmpl (@tmpls) {
		printf $fmt, $tmpl->{'id'}, $tmpl->{'name'};
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the available templates for new virtual servers.\n";
print "\n";
print "virtualmin list-templates [--name-only | --multiline]\n";
print "                          [--deleted]\n";
exit(1);
}

