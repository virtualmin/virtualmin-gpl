#!/usr/local/bin/perl

=head1 delete-template.pl

Removes one virtual server template.

This command can be used to delete a Vrtualmin template, specified either by
name with the C<--name> parameter, or by ID with the C<--id> flag. Any virtual
servers still using the template will be un-effected.

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
	$0 = "$pwd/delete-templates.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "delete-templates.pl must be run as root";
	}
@OLDARGV = @ARGV;

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
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
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
$tmpl->{'standard'} && &usage("Default settings templates cannot be deleted");

# Delete it
&delete_template($tmpl);
print "Deleted template $tmpl->{'name'} with ID $tmpl->{'id'}\n";
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Removes one virtual server template.\n";
print "\n";
print "virtualmin delete-template --name template-name | --id template-id\n";
exit(1);
}

