#!/usr/local/bin/perl
# Changes the owner limits for some virtual server

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/modify-limits.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-limits.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
@all_allow = (@opt_features, "virt", @feature_plugins);
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--user") {
		$user = lc(shift(@ARGV));
		}
	elsif ($a eq "--max-mailboxes") {
		$mailboxes = shift(@ARGV);
		$mailboxes eq "UNLIMITED" || $mailboxes =~ /^\d+$/ || &usage("Maximum mailboxes must be a number or UNLIMITED");
		}
	elsif ($a eq "--max-dbs") {
		$dbs = shift(@ARGV);
		$dbs eq "UNLIMITED" || $dbs =~ /^\d+$/ || &usage("Maximum databases must be a number or UNLIMITED");
		}
	elsif ($a eq "--max-doms") {
		$doms = shift(@ARGV);
		$doms eq "NONE" || $doms eq "UNLIMITED" || $doms =~ /^\d+$/ || &usage("Maximum sub-servers must be a number, NONE or UNLIMITED");
		}
	elsif ($a eq "--max-aliasdoms") {
		$aliasdoms = shift(@ARGV);
		$aliasdoms eq "UNLIMITED" || $aliasdoms =~ /^\d+$/ || &usage("Maximum alias servers must be a number or UNLIMITED");
		}
	elsif ($a eq "--max-realdoms") {
		$realdoms = shift(@ARGV);
		$realdoms eq "UNLIMITED" || $realdoms =~ /^\d+$/ || &usage("Maximum real servers must be a number or UNLIMITED");
		}
	elsif ($a eq "--max-aliases") {
		$aliases = shift(@ARGV);
		$aliases eq "UNLIMITED" || $aliases =~ /^\d+$/ || &usage("Maximum aliases must be a number or UNLIMITED");
		}
	elsif ($a eq "--max-mongrels") {
		$mongrels = shift(@ARGV);
		$mongrels eq "UNLIMITED" || $mongrels =~ /^[1-9]\d*$/ || &usage("Maximum Mongrel instances number or UNLIMITED");
		}
	elsif ($a eq "--can-dbname") {
		$candbname = 1;
		}
	elsif ($a eq "--cannot-dbname") {
		$cannotdbname = 1;
		}
	elsif ($a eq "--can-rename") {
		$canrename = 1;
		}
	elsif ($a eq "--cannot-rename") {
		$cannotrename = 1;
		}
	elsif ($a eq "--force-under") {
		$forceunder = 1;
		}
	elsif ($a eq "--noforce-under") {
		$noforceunder = 1;
		}
	elsif ($a eq "--read-only") {
		$readonly = 1;
		}
	elsif ($a eq "--read-write") {
		$readwrite = 1;
		}
	elsif ($a eq "--allow") {
		$allow = shift(@ARGV);
		&indexof($allow, @all_allow) >= 0 || &usage("Feature to allow $allow is not known. Valid features are : ".join(" ", @all_allow));
		push(@allow, $allow);
		}
	elsif ($a eq "--disallow") {
		$disallow = shift(@ARGV);
		&indexof($disallow, @all_allow) >= 0 || &usage("Feature to disallow $allow is not known. Valid features are : ".join(" ", @all_allow));
		push(@disallow, $disallow);
		}
	elsif ($a eq "--can-edit") {
		$edit = shift(@ARGV);
		&indexof($edit, @edit_limits) >= 0 || &usage("Capability to allow editing of $edit is not valid. Known capabilities are : ".join(" ", @edit_limits));
		push(@canedit, $edit);
		}
	elsif ($a eq "--cannot-edit") {
		$edit = shift(@ARGV);
		&indexof($edit, @edit_limits) >= 0 || &usage("Capability to disallow editing of $edit is not valid : ".join(" ", @edit_limits));
		push(@cannotedit, $edit);
		}
	elsif ($a eq "--shell") {
		$shellmode = shift(@ARGV);
		@shells = grep { $_->{'owner'} } &list_available_shells();
		($shell) = grep { $_->{'shell'} eq $shellmode ||
				  $_->{'id'} eq $shellmode } @shells;
		$shell || &usage("Unknown or un-supported shell $shellmode");
		}
	else {
		usage();
		}
	}

# Find the domain
$domain || $user || usage();
if ($domain) {
	$dom = &get_domain_by("dom", $domain);
	$dom || usage("Virtual server $domain does not exist.");
	}
else {
	$dom = &get_domain_by("user", $user, "parent", undef);
	$dom || usage("Virtual server owner $user does not exist.");
	}
$old = { %$dom };
$tmpl = &get_template($dom->{'template'});
$dom->{'parent'} && &usage("Limits can only be modified in top-level virtual servers");

# Update domain object
if (defined($mailboxes)) {
	$dom->{'mailboxlimit'} = $mailboxes eq "UNLIMITED" ? undef : $mailboxes;
	}
if (defined($dbs)) {
	$dom->{'dbslimit'} = $dbs eq "UNLIMITED" ? undef : $dbs;
	}
if (defined($doms)) {
	$dom->{'domslimit'} = $doms eq "NONE" ? undef :
			      $doms eq "UNLIMITED" ? "*" : $doms;
	}
if (defined($aliases)) {
	$dom->{'aliaslimit'} = $aliases eq "UNLIMITED" ? undef : $aliases;
	}
if (defined($aliasdoms)) {
	$dom->{'aliasdomslimit'} = $aliasdoms eq "UNLIMITED" ? undef
							     : $aliasdoms;
	}
if (defined($realdoms)) {
	$dom->{'realdomslimit'} = $realdoms eq "UNLIMITED" ? undef
							   : $realdoms;
	}
if (defined($mongrels)) {
	$dom->{'mongrelslimit'} = $mongrels eq "UNLIMITED" ? undef : $mongrels;
	}
$dom->{'nodbname'} = $candbname ? 0 :
		     $cannotdbname ? 1 : $dom->{'nodbname'};
$dom->{'norename'} = $canrename ? 0 :
		     $cannotrename ? 1 : $dom->{'norename'};
$dom->{'forceunder'} = $forceunder ? 1 :
		       $noforceunder ? 0 : $dom->{'forceunder'};
$dom->{'readonly'} = $readonly ? 1 :
		     $readwrite ? 0 : $dom->{'readonly'};
foreach $a (@allow) {
	$dom->{'limit_'.$a} = 1;
	}
foreach $a (@disallow) {
	$dom->{'limit_'.$a} = 0;
	}
foreach $e (@canedit) {
	$dom->{'edit_'.$e} = 1;
	}
foreach $e (@cannotedit) {
	$dom->{'edit_'.$e} = 0;
	}

# Save domain object
&set_all_null_print();
&save_domain($dom);

# Save the Webmin user
&modify_webmin($dom, $old);

# Update the domain owner user's shell
if ($shell && $dom->{'unix'}) {
	$user = &get_domain_owner($dom);
	$olduser = { %$user };
	$user->{'shell'} = $shell->{'shell'};
	&modify_user($user, $olduser, $dom);
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $dom);
print "Successfully updated limits for $dom->{'user'}\n";

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Changes the restrictions on a virtual server owner.\n";
print "\n";
print "usage: modify-limits.pl  --domain domain.name | --user name\n";
print "                         [--max-doms max|UNLIMITED|NONE]\n";
print "                         [--max-aliasdoms max|UNLIMITED]\n";
print "                         [--max-realdoms max|UNLIMITED]\n";
print "                         [--max-mailboxes max|UNLIMITED]\n";
print "                         [--max-dbs max|UNLIMITED]\n";
print "                         [--max-aliases max|UNLIMITED]\n";
print "                         [--can-dbname] | [--cannot-dbname]\n";
print "                         [--can-rename] | [--cannot-rename]\n";
print "                         [--force-under] | [--noforce-under]\n";
print "                         [--read-only] | [--read-write]\n";
print "                         [--allow feature] ...\n";
print "                         [--disallow feature] ...\n";
print "                         [--can-edit capability] ...\n";
print "                         [--cannot-edit capability] ...\n";
print "                         [--shell \"nologin\" | \"ftp\" | \"ssh\"]\n";
exit(1);
}


