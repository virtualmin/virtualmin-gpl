#!/usr/local/bin/perl

=head1 create-template.pl

Creates a template for use by new domains.

This command can be used to create a new virtual server template, whose name
is set by the C<--name> parameter. You can either have the template created
completely empty (so that all settings inherit from the default template)
with the C<--empty> flag, or you can clone an existing template with the
C<--clone> flag followed by a template name.

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
	$0 = "$pwd/create-template.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-template.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--name") {
		$tmplname = shift(@ARGV);
		}
	elsif ($a eq "--empty") {
		$empty = 1;
		}
	elsif ($a eq "--clone") {
		$clonename = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Check for required parameters
$tmplname || &usage("Missing --name parameter");
$empty || $clonename || &usage("Missing either --empty or --clone parameter");
$empty && $clonename && &usage("Only one of --empty or --clone can be given");

# Check for clash
@tmpls = &list_templates();
($clash) = grep { $_->{'name'} eq $tmplname } @tmpls;
$clash && &usage("A template with the same name already exists");
if ($clonename) {
	($clone) = grep { $_->{'name'} eq $clonename ||
			  $_->{'id'} eq $clonename } @tmpls;
	$clone || &usage("The template to clone does not exist");
	}

if ($empty) {
	# Create as empty
	$tmpl = { };
	}
else {
	# Copy parameters from clone source
	$tmpl = { %$clone };
	$tmpl->{'id'} = undef;
        $tmpl->{'standard'} = 0;
        $tmpl->{'default'} = 0;
	}
$tmpl->{'name'} = $tmplname;

# Save the template, and perhaps cloned scripts
&save_template($tmpl);
if ($clone) {
	$scripts = &list_template_scripts($clone);
	&save_template_scripts($tmpl, $scripts);
	}

print "Created template $tmplname with ID $tmpl->{'id'}\n";
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Adds a new Virtualmin server template, either empty or copied from\n";
print "an existing template.\n";
print "\n";
print "virtualmin create-template --name template-name\n";
print "                           --empty | --clone original-name\n";
exit(1);
}

