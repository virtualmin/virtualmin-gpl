#!/usr/local/bin/perl
# Adds an extra administrator to a virtual server

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
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
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
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
	else {
		&usage();
		}
	}

$domain && $name || &usage("Missing domain name or login name");
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
$d->{'parent'} && &usage("Virtual server $domain is not a parent server");
@admins = &list_extra_admins($d);

# Check for a clash
$name eq "webmin" && &usage("The login name webmin is reserved");
&obtain_lock_webmin();
&require_acl();
($clash) = grep { $_->{'name'} eq $name } &acl::list_users();
$clash && &usage("The login name $name is already in use");

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

# Create the admin
&create_extra_admin($admin, $d);
&release_lock_webmin();
&virtualmin_api_log(\@OLDARGV, $d);
print "Extra administrator $name created successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Creates a new extra administrator associated with some virtual server.\n";
print "\n";
print "usage: create-admin.pl --domain domain.name\n";
print "                       --name login\n";
print "                       [--pass password]\n";
print "                       [--desc description]\n";
print "                       [--desc description]\n";
print "                       [--create] [--rename] [--features] [--modules]\n";
print "                       [--edit capability]*\n";
exit(1);
}

