#!/usr/local/bin/perl
# Lists all users in some domain

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/list-users.pl";
require './virtual-server-lib.pl';
$< == 0 || die "list-users.pl must be run as root";

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--domain-user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all = 1;
		}
	elsif ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--include-owner") {
		$owner = 0;
		}
	elsif ($a eq "--user") {
		$usernames{shift(@ARGV)} = 1;
		}
	elsif ($a eq "--mail-size") {
		$mailsize = 1;
		}
	else {
		&usage();
		}
	}

# Parse args and get domains
@dnames || @users || $all || &usage();
if ($all) {
	@doms = &list_domains();
	}
else {
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}

foreach $d (@doms) {
	@users = &list_domain_users($d, $owner, 0, 0, 0);
	if ($multi) {
		# Show attributes on separate lines
		foreach $u (@users) {
			next if (%usernames && !$usernames{$u->{'user'}} &&
				 !$usernames{&remove_userdom($u->{'user'}, $d)});
				 
			print &remove_userdom($u->{'user'}, $d),"\n";
			print "    Domain: $d->{'dom'}\n";
			print "    Unix username: ",$u->{'user'},"\n";
			print "    Real name: ",$u->{'real'},"\n";
			if (defined($u->{'plainpass'})) {
				print "    Password: ",$u->{'plainpass'},"\n";
				}
			$pass = $u->{'pass'};
			$disable = $pass =~ s/^\!//;
			print "    Encrypted password: ",$pass,"\n";
			print "    Disabled: ",($disable ? "Yes" : "No"),"\n";
			print "    Home directory: ",$u->{'home'},"\n";
			print "    FTP access: ",&ftp_shell($u),"\n";
			print "    User type: ",($u->{'domainowner'} ? "Server owner" :
						 $u->{'webowner'} ? "Website manager" :
							"Normal user"),"\n";
			if ($u->{'mailquota'}) {
				print "    Mail server quota: ",$u->{'qquota'},"\n";
				}
			if ($u->{'unix'} && &has_home_quotas() && !$u->{'noquota'}) {
				print "    Home quota: ",
				      &quota_show($u->{'quota'}, "home"),"\n";
				print "    Home quota used: ",
				      &quota_show($u->{'uquota'}, "home"),"\n";
				}
			if ($u->{'unix'} && &has_mail_quotas() && !$u->{'noquota'}) {
				print "    Mail quota: ",
				      &quota_show($u->{'mquota'}, "mail"),"\n";
				print "    Mail quota used: ",
				      &quota_show($u->{'umquota'}, "mail"),"\n";
				}
			if ($mailsize) {
				($msize) = &mail_file_size($u);
				print "    Mail file size: ",&nice_size($msize),"\n";
				}
			if ($u->{'email'}) {
				print "    Email address: ",$u->{'email'},"\n";
				}
			if (@{$u->{'extraemail'}} && !$u->{'noextra'}) {
				print "    Extra addresses: ",join(" ", @{$u->{'extraemail'}}),"\n";
				}
			if ($config{'spam'}) {
				print "    Check spam and viruses: ",
					!$d->{'spam'} ? "Disabled for domain" :
					$u->{'nospam'} ? "No" : "Yes","\n";
				}
			@dblist = ( );
			foreach $db (@{$u->{'dbs'}}) {
				push(@dblist, $db->{'name'}." ($db->{'type'})");
				}
			if (@dblist) {
				print "    Databases: ",join(", ", @dblist),"\n";
				}
			if (!$u->{'noalias'}) {
				foreach $t (@{$u->{'to'}}) {
					print "    Forward mail to: $t\n";
					}
				}
			if (@{$u->{'secs'}}) {
				print "    Secondary groups: ",join(" ", @{$u->{'secs'}}),"\n";
				}
			}
		}
	else {
		# Show all on one line
		if (@doms > 1) {
			print "Users in domain $d->{'dom'} :\n"; 
			}
		$fmt = "%-20.20s %-20.20s %-4.4s %-10.10s %-4.4s %-15.15s\n";
		printf $fmt, "User", "Real name", "Mail", "FTP", "DBs", "Quota";
		printf $fmt, ("-" x 20), ("-" x 20), ("-" x 4), ("-" x 10), ("-" x 4),
			     ("-" x 15);
		foreach $u (@users) {
			printf $fmt, &remove_userdom($u->{'user'}, $d),
				    $u->{'real'},
				    $u->{'email'} ? "Yes" : "No",
				    &ftp_shell($u),
				    scalar(@{$u->{'dbs'}}) || "No",
				    $u->{'mailquota'} ? $u->{'qquota'} :
				    &has_home_quotas() ? 
					    &quota_show($u->{'quota'}, "home") :
					    "NA";
			}
                if (@doms > 1) {
                        print "\n";
                        }
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the mail, FTP and database users in one or more virtual servers.\n";
print "\n";
print "usage: list-users.pl   [--all-domains] | [--domain domain.name] |\n";
print "                       [--domain-user username]*\n";
print "                       [--multiline]\n";
print "                       [--include-owner]\n";
print "                       [--user name]\n";
exit(1);
}

sub ftp_shell
{
local ($u) = @_;
return  !$u->{'unix'} && !$u->{'shell'} ? "Mail only" :
        $u->{'shell'} eq $config{'ftp_shell'} ? "Yes" :
        $config{'jail_shell'} &&
	$u->{'shell'} eq $config{'jail_shell'} ? "Jailed" :
	$u->{'shell'} eq $config{'shell'} ? "No" :
	"Shell $u->{'shell'}";
}

