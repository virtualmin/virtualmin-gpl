#!/usr/local/bin/perl

=head1 create-admin.pl

Creates an extra administrator for a virtual server

This command creates a new administrator associated with an existing
virtual server.  You must supply the C<--domain> parameter to
specify the server and C<--name> to set the admin login name. The C<--pass> and
C<--desc> options should also be given, to specify the initial password and
a description for the account respectively. To specify a contact email address
for the admin, use the C<--email> flag followed by the address.

Basic permissions for the account can be added using the C<--create>, C<--rename>, C<--features> and C<--modules> parameters. These allow the admin to create new
servers, rename servers, use Webmin modules for server features, and use other Webmin modules, respectively.

The extra admin's editing capabilities for virtual servers can be set using
the C<--edit> parameter, followed by a capability name (like users or aliases).
This can be given multiple times, as in the command below :

  virtualmin create-admin --domain foo.com --name fooadmin --pass smeg --desc "Extra administrator" --edit users --edit aliases

That command would create an extra administrator account who can only edit
mail users and mail aliases in the virtual server I<foo.com> and any sub-servers.

By default, the extra administrator will have access to all virtual servers
owned by the top-level server it is created in. However, this can be restricted
using the C<--allowed-domain> flag followed by a domain name, to which the
admin will be limited to. It can be given multiple times to allow access to
more than one virtual server.

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
	$0 = "$pwd/create-admin.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "create-admin.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
$norename = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--name") {
		$name = shift(@ARGV);
		$name =~ /^[a-z0-9\_\.]+$/i ||
			&usage("Invalid extra administrator name");
		}
	elsif ($a eq "--desc") {
		$desc = shift(@ARGV);
		}
	elsif ($a eq "--email") {
		$email = shift(@ARGV);
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--passfile") {
		$pass = &read_file_contents(shift(@ARGV));
		$pass =~ s/\r|\n//g;
		}
	elsif ($a eq "--edit") {
		$edit = shift(@ARGV);
		&indexof($edit, @edit_limits) >= 0 ||
			&usage("Unknown edit capability. Valid capabilities are : ".join(" ", @edit_limits));
		push(@edits, $edit);
		}
	elsif ($a eq "--can-create") {
		$create = 1;
		}
	elsif ($a eq "--can-rename") {
		$norename = 0;
		}
	elsif ($a eq "--can-features") {
		$features = 1;
		}
	elsif ($a eq "--can-modules") {
		$modules = 1;
		}
	elsif ($a eq "--allowed-domain") {
		push(@allowednames, shift(@ARGV));
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown flag $a");
		}
	}

$domain && $name || &usage("Missing domain name or login name");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$d->{'parent'} && &usage("Virtual server $domain is not a parent server");
$d->{'webmin'} || &usage("Virtual server $domain does not have a Webmin login enabled");
@admins = &list_extra_admins($d);

# Check for a clash
$name eq "webmin" && &usage("The login name webmin is reserved");
&obtain_lock_webmin();
&require_acl();
($clash) = grep { $_->{'name'} eq $name } &acl::list_users();
$clash && &usage("The login name $name is already in use");

# Validate allowed domains
@allowed = ( );
foreach $aname (@allowednames) {
	$a = &get_domain_by("dom", $aname);
	$a || &usage("The allowed virtual server $aname does not exist");
	$a->{'user'} eq $d->{'user'} ||
		&usage("The allowed virtual server $a->{'dom'} is not owned ".
		       "by the same user as $d->{'dom'}");
	push(@allowed, $a->{'id'});
	}

# Create the object
$admin = { 'name' => $name,
	   'desc' => $desc,
	   'pass' => $pass,
	   'create' => $create,
	   'norename' => $norename,
	   'features' => $features,
	   'modules' => $modules,
	 };
foreach $e (@edits) {
	$admin->{'edit_'.$e} = 1;
	}
$admin->{'email'} = $email if ($email);
if (@allowed) {
	$admin->{'doms'} = join(" ", @allowed);
	}

# Create the admin
&create_extra_admin($admin, $d);
&release_lock_webmin();
&run_post_actions_silently();
&virtualmin_api_log(\@OLDARGV, $d);
print "Extra administrator $name created successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Creates a new extra administrator associated with some virtual server.\n";
print "\n";
print "virtualmin create-admin --domain domain.name\n";
print "                        --name login\n";
print "                        [--pass password | --passfile password-file]\n";
print "                        [--desc description]\n";
print "                        [--email user\@domain]\n";
print "                        [--create] [--rename]\n";
print "                        [--features] [--modules]\n";
print "                        [--edit capability]*\n";
print "                        [--allowed-domain domain]*\n";
exit(1);
}

