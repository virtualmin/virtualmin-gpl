#!/usr/local/bin/perl

=head1 get-template.pl

Outputs all settings in a template.

XXX

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/get-templates.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "get-templates.pl must be run as root";
	}

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name") {
		$tmplname = shift(@ARGV);
		}
	elsif ($a eq "--id") {
		$tmplid = shift(@ARGV);
		}
	elsif ($a eq "--inherited") {
		$inherited = 1;
		}
	else {
		&usage();
		}
	}

# Validate args, get the template
@tmpls = &list_templates();
if (defined($tmplname)) {
	($tmpl) = grep { $_->{'name'} eq $tmplname } @tmpls;
	$tmpl || &usage("No template with name $tmplname found");
	}
elsif (defined($tmplid)) {
	($tmpl) = grep { $_->{'id'} eq $tmplid } @tmpls;
	$tmpl || &usage("No template with ID $tmplid found");
	}
else {
	&usage("Missing --name or --id parameter");
	}
if ($inherited) {
	$tmpl = &get_template($tmpl->{'id'});
	}

# Dump the contents
foreach my $k (sort { $a cmp $b } keys %$tmpl) {
	$tmpl->{$k} =~ s/\r//g;
	$tmpl->{$k} =~ s/\\/\\\\/g;
	$tmpl->{$k} =~ s/\n/\\n/g;
	print "$k: $tmpl->{$k}\n";
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Outputs all settings in some virtual server template.\n";
print "\n";
print "usage: get-template.pl --name template-name | --id template-id\n";
print "                       [--inherited]\n";
exit(1);
}

