#!/usr/local/bin/perl
# Updates an extra admin associated with some virtual server

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/modify-admin.pl";
require './virtual-server-lib.pl';
$< == 0 || die "modify-admin.pl must be run as root";

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = shift(@ARGV);
		}
	elsif ($a eq "--name") {
		$name = shift(@ARGV);
		}
	elsif ($a eq "--newname") {
		$newname = shift(@ARGV);
		}
	elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--desc") {
		$desc = shift(@ARGV);
		}
	elsif ($a eq "--can-edit" || $a eq "--cannot-edit") {
		$edit = shift(@ARGV);
		&indexof($edit, @edit_limits) >= 0 ||
			&usage("Unknown edit capability. Valid capabilities are : ".join(" ", @edit_limits));
		if ($a eq "--can-edit") { push(@canedits, $edit); }
		else { push(@cannotedits, $edit); }
		}
	elsif ($a eq "--can-create") {
		$create = 1;
		}
	elsif ($a eq "--cannot-create") {
		$create = 0;
		}
	elsif ($a eq "--can-rename") {
		$norename = 0;
		}
	elsif ($a eq "--cannot-rename") {
		$norename = 1;
		}
	elsif ($a eq "--can-features") {
		$features = 1;
		}
	elsif ($a eq "--cannot-features") {
		$features = 0;
		}
	elsif ($a eq "--can-modules") {
		$modules = 1;
		}
	elsif ($a eq "--cannot-modules") {
		$modules = 0;
		}
	else {
		&usage();
		}
	}

$domain && $name || &usage();
$d = &get_domain_by("dom", $domain);
$d || usage("Virtual server $domain does not exist");
@admins = &list_extra_admins($d);

# Find the admin
($admin) = grep { $_->{'name'} eq $name } @admins;
$admin || &usage("Extra administrator $name does not exist in this virtual server");
$old = { %$admin };

# Update the object
if (defined($newname)) {
	&require_acl();
	($clash) = grep { $_->{'name'} eq $newname } &acl::list_users();
	$clash && &usage("The login name $newname is already in use");
	$admin->{'name'} = $newname;
	}
if (defined($pass)) {
	$admin->{'pass'} = $pass;
	}
if (defined($desc)) {
	$admin->{'desc'} = $desc;
	}
if (defined($create)) {
	$admin->{'create'} = $create;
	}
if (defined($norename)) {
	$admin->{'norename'} = $norename;
	}
if (defined($features)) {
	$admin->{'features'} = $features;
	}
if (defined($modules)) {
	$admin->{'modules'} = $modules;
	}
foreach $e (@canedits) {
	$admin->{'edit_'.$e} = 1;
	}
foreach $e (@cannotedits) {
	$admin->{'edit_'.$e} = 0;
	}

# Save him
&modify_extra_admin($admin, $old, $d);
print "Extra administrator $name modified successfully\n";

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Modifies an extra administrator associated with some virtual server.\n";
print "\n";
print "usage: modify-admin.pl --domain domain.name\n";
print "                       --name login\n";
print "                       [--newname login]\n";
print "                       [--pass password]\n";
print "                       [--desc description]\n";
print "                       [--can-create] | [--cannot-create]\n";
print "                       [--can-rename] | [--cannot-rename]\n";
print "                       [--can-features] | [--cannot-features]\n";
print "                       [--can-modules] | [--cannot-modules]\n";
print "                       [--can-edit capability]*\n";
print "                       [--cannot-edit capability]*\n";
exit(1);
}

