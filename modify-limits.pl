#!/usr/local/bin/perl

=head1 modify-limits.pl

Changes the owner limits for some virtual server

This command allows you to change various limits that apply to the owner
of a virtual server when they are logged into the web interface. The domain
to effect is selected with the C<--domain> or C<--user> flag, which must be
followed by a top-level domain name or administrator's username respectively.

To grant the domain owner access to some Virtualmin feature (such as C<mysql>
or C<webalizer>), use the C<--allow> flag followed by the feature code. To
prevent access, use C<--disallow> instead. Both flags can be given multiple
times.

To change the number of domains that can be created, use the C<--max-doms>
flag followed by a number or the word C<UNLIMITED>. To prevent him from
creating domains at all, use C<--max-doms NONE>. Separate limits can be imposed
on the number of alias and non-alias domains with the C<--max-aliasdoms> and
C<--max-realdoms> flags.

Limits on the numbers of databases, mailboxes and mail aliases that can be
created are set with the C<--max-dbs>, C<--max-mailboxes> and C<--max-aliases>
flags respectively. Each must be followed either with a number, or the word
C<UNLIMITED>.

To grant the domain owner access to Virtualmin UI capabilities such as editing
aliases or users, the C<--can-edit> flag should be used, followed by a
capability code. Supported codes and their meanings are :

C<domain> - Edit Virtual server details such as the description and password

C<users> - Manage mail / FTP users

C<aliases> - Manage email aliases

C<dbs> - Manage databases

C<scripts> - List and install scripts

C<ip> - Change the IP address of virtual servers

C<dnsip> - Change the externally visible (DNS) IP address of virtual servers

C<ssl> - Generate and upload SSL certificates

C<forward> - Setup proxying and frame forwarding

C<redirect> - Create and edit website aliases and redirects

C<admins> - Manage extra administrators

C<spam> - Edit spam filtering, delivery and clearing settings

C<phpver> - Change PHP versions

C<phpmode> - Change website options and PHP execution mode

C<mail> - Edit email-related settings

C<backup> - Backup virtual servers

C<sched> - Schedule automatic backups

C<restore> - Restore virtual servers (databases and home directories only)

C<sharedips> - Move to different shared IP addresses

C<catchall> - Create catchall email aliases

C<html> - Use the HTML editor

C<allowedhosts> - Can edit the remote IPs allowed access to MySQL

C<passwd> - Can change a virtual server's password

C<spf> - Can edit the DNS sender permitted from record

C<records> - Can edit other DNS records

C<disable> - Disable virtual servers

C<delete> - Delete virtual servers

Access to capabilities can also be taken away with the C<--cannot-edit> flag.

To restrict the virtual server owner to only installing certain scripts 
(when using Virtualmin Pro), you can use the C<--scripts> flag followed by
a quoted list of script codes. To grant access to all script installers, use
the C<--all-scripts> flag instead.

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
	$0 = "$pwd/modify-limits.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-limits.pl must be run as root";
	}
@OLDARGV = @ARGV;

# Parse command-line args
@all_allow = (@opt_features, "virt", &list_feature_plugins());
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
	elsif ($a eq "--can-migrate") {
		$canmigrate = 1;
		}
	elsif ($a eq "--cannot-migrate") {
		$cannotmigrate = 1;
		}
	elsif ($a eq "--force-under") {
		$forceunder = 1;
		}
	elsif ($a eq "--noforce-under") {
		$noforceunder = 1;
		}
	elsif ($a eq "--safe-under") {
		$safeunder = 1;
		}
	elsif ($a eq "--nosafe-under") {
		$nosafeunder = 1;
		}
	elsif ($a eq "--ipfollow") {
		$ipfollow = 1;
		}
	elsif ($a eq "--noipfollow") {
		$noipfollow = 1;
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
	elsif ($a eq "--scripts") {
		$allowedscripts = shift(@ARGV);
		@sc = split(/\s+/, $allowedscripts);
		foreach $s (@sc) {
			&get_script($s) ||
				&usage("Unknown script code $s");
			}
		}
	elsif ($a eq "--all-scripts") {
		$allowedscripts = "";
		}
	elsif ($a eq "--shell") {
		$shellmode = shift(@ARGV);
		@shells = grep { $_->{'owner'} } &list_available_shells();
		($shell) = grep { $_->{'shell'} eq $shellmode ||
				  $_->{'id'} eq $shellmode } @shells;
		$shell || &usage("Unknown or un-supported shell $shellmode");
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Find the domain
$domain || $user || usage("No domain or user specified");
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
$dom->{'migrate'} = $canmigrate ? 1 :
		    $cannotmigrate ? 0 : $dom->{'migrate'};
$dom->{'forceunder'} = $forceunder ? 1 :
		       $noforceunder ? 0 : $dom->{'forceunder'};
$dom->{'safeunder'} = $safeunder ? 1 :
		      $nosafeunder ? 0 : $dom->{'safeunder'};
$dom->{'ipfollow'} = $ipfollow ? 1 :
		      $noipfollow ? 0 : $dom->{'ipfollow'};
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
if (defined($allowedscripts)) {
	$dom->{'allowedscripts'} = $allowedscripts;
	}

# Save domain object
&set_all_null_print();
&save_domain($dom);

# Save the Webmin user
&modify_webmin($dom, $old);

# Update the domain owner user's shell
if ($shell && $dom->{'unix'}) {
	&change_domain_shell($dom, $shell->{'shell'});
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV, $dom);
print "Successfully updated limits for $dom->{'user'}\n";

sub usage
{
print $_[0],"\n\n" if ($_[0]);
print "Changes the restrictions on a virtual server owner.\n";
print "\n";
print "virtualmin modify-limits --domain domain.name | --user name\n";
print "                        [--max-doms max|UNLIMITED|NONE]\n";
print "                        [--max-aliasdoms max|UNLIMITED]\n";
print "                        [--max-realdoms max|UNLIMITED]\n";
print "                        [--max-mailboxes max|UNLIMITED]\n";
print "                        [--max-dbs max|UNLIMITED]\n";
print "                        [--max-aliases max|UNLIMITED]\n";
print "                        [--can-dbname] | [--cannot-dbname]\n";
print "                        [--can-rename] | [--cannot-rename]\n";
print "                        [--can-migrate] | [--cannot-migrate]\n";
print "                        [--force-under] | [--noforce-under]\n";
print "                        [--safe-under] | [--nosafe-under]\n";
print "                        [--ipfollow] | [--noipfollow]\n";
print "                        [--read-only] | [--read-write]\n";
print "                        [--allow feature]*\n";
print "                        [--disallow feature]*\n";
print "                        [--can-edit capability]*\n";
print "                        [--cannot-edit capability]*\n";
print "                        [--shell nologin|ftp|ssh]\n";
exit(1);
}


