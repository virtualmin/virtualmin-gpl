#!/usr/local/bin/perl

=head1 modify-custom.pl

Modify custom fields for a virtual server

This program updates the value of one or more fields for a single virtual
server. The parameter C<--domain> must be given, and must be followed by the
domain name of the server to update. You must also supply the C<--set> parameter
at least once, which has to be followed by the code for the field to update
and the new value.

For menu-type custom fields, the value must be the underlying value, not
the one that is displayed to the user. For yes/no fields, the value must be
either <tt>1</tt> for Yes or <tt>0</tt> for No.

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
	$0 = "$pwd/modify-custom.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-custom.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--set") {
		$field = shift(@ARGV);
		if ($field =~ /^(\S+)\s+(.*)$/) {
			# Name and value in one parameter, such as from HTTP API
			$field = $1;
			$value = $2;
			}
		else {
			$value = shift(@ARGV);
			}
		$field && defined($value) ||
		     &usage("--set must be followed by a field name and value");
		push(@set, [ $field, $value ]);
		}
	elsif ($a eq "--allow-missing") {
		$allow_missing = 1;
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
$domain && @set || &usage("No domain or fields to set specified");

# Get the domain
$dom = &get_domain_by("dom", $domain);
$dom || usage("Virtual server $domain does not exist.");
$old = { %$dom };

# Run the before script
&set_domain_envs($old, "MODIFY_DOMAIN", $dom);
$merr = &making_changes();
&reset_domain_envs($old);
&usage($merr) if ($merr);

# Update all fields
@fields = &list_custom_fields();
foreach $f (@set) {
	($field) = grep { $_->{'name'} eq $f->[0] ||
			  $_->{'desc'} eq $f->[0] } @fields;
	$field || $allow_missing ||
		&usage("No custom field named $f->[0] exists");
	$dom->{'field_'.($field->{'name'} || $f->[0])} = $f->[1];
	}
&save_domain($dom);

# Run the after script
&set_domain_envs($dom, "MODIFY_DOMAIN", undef, $old);
&made_changes();
&reset_domain_envs($dom);

&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV, $dom);
print "Custom field values in $domain successfully updated\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Sets the values of one or more custom fields for a virtual server\n";
print "\n";
print "virtualmin modify-custom --domain name\n";
print "                        <--set \"field value\">+\n";
exit(1);
}


