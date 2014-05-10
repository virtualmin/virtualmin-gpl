#!/usr/local/bin/perl

=head1 modify-template.pl

Changes one or more settings in a template.

This command can be used to change several settings in a Virtualmin template,
specified either by name with the C<--name> parameter, or by ID with the
C<--id> flag.

The setting to change is specified with the C<--setting> flag, followed by
a template variable name like I<uquota>. Each occurrance of this flag must
be followed by the C<--value> parameter, followed by the value to use for
the previously named setting.

Multi-line values can be instead read from a file, by using the C<--value-file>
parameter followed by a full path to a file.

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
	$0 = "$pwd/modify-templates.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-templates.pl must be run as root";
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
	elsif ($a eq "--setting") {
		push(@names, shift(@ARGV));
		}
	elsif ($a eq "--value") {
		push(@values, shift(@ARGV));
		}
	elsif ($a eq "--value-file") {
		$f = shift(@ARGV);
		$v = &read_file_contents($f);
		defined($v) || &usage("Failed to read file $f : $!");
		push(@values, $v);
		}
	elsif ($a eq "--fix-options") {
		$fixoptions = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate args, get the template
scalar(@names) && scalar(@values) || $fixoptions ||
	&usage("At least one --name and --value parameter must be given");
scalar(@names) == scalar(@values) ||
	&usage("The number of --name and --value parameters must be the same");
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
my $file = $tmpl->{'file'} || $module_config_file;
&lock_file($file);

# Update the template
for($i=0; $i<scalar(@names); $i++) {
	$tmpl->{$names[$i]} = $values[$i];
	}
&save_template($tmpl);

# Apply Apache Options line fix
if ($fixoptions) {
	&fix_options_template($tmpl, 1);
	}
&unlock_file($file);

# Run all post-save functions
foreach my $f (@features) {
	$psfunc = "postsave_template_".$f;
	if (defined(&$psfunc)) {
		&$psfunc($tmpl);
		}
	}

# Update all Webmin users
&set_all_null_print();
&modify_all_webmin($tmpl->{'standard'} ? undef : $tmpl->{'id'});
&run_post_actions();

print "Modified ",scalar(@names)," settings in template $tmpl->{'name'}\n";
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes one or more settings in a virtual server template\n";
print "\n";
print "virtualmin modify-template --name template-name | --id template-id\n";
print "                          [--setting name --value newvalue]+\n";
print "                          [--fix-options]\n";
exit(1);
}

