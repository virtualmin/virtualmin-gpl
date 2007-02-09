#!/usr/local/bin/perl
# Lists all virtual servers

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/list-domains.pl";
require './virtual-server-lib.pl';
$< == 0 || die "list-domains.pl must be run as root";
use POSIX;

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--with-feature") {
		$with = shift(@ARGV);
		}
	elsif ($a eq "--without-feature") {
		$without = shift(@ARGV);
		}
	else {
		&usage();
		}
	}

if (@domains) {
	# Just showing listed domains
	foreach $domain (@domains) {
		$d = &get_domain_by("dom", $domain);
		$d || &usage("Virtual server $domain does not exist");
		push(@doms, $d);
		}
	}
else {
	# Showing all domains
	@doms = &list_domains();
	}
@doms = sort { $a->{'user'} cmp $b->{'user'} ||
	       $a->{'created'} <=> $b->{'created'} } @doms;

# Limit to those with/without some feature
if ($with) {
	@doms = grep { $_->{$with} } @doms;
	}
if ($without) {
	@doms = grep { !$_->{$without} } @doms;
	}

if ($multi) {
	# Show attributes on multiple lines
	foreach $d (@doms) {
		local @users = &list_domain_users($d, 0, 1, 0, 1);
		local ($duser) = grep { $_->{'user'} eq $d->{'user'} } @users;
		print "$d->{'dom'}\n";
		print "    ID: $d->{'id'}\n";
		print "    Type: ",($d->{'alias'} ? "Alias" :
				    $d->{'parent'} ? "Sub-server" :
						     "Top-level server"),"\n";
		if ($d->{'alias'}) {
			$aliasdom = &get_domain_by("id", $d->{'alias'});
			print "    Real domain: $aliasdom->{'dom'}\n";
			}
		elsif ($d->{'parent'}) {
			$parentdom = &get_domain_by("id", $d->{'parent'});
			print "    Parent domain: $parentdom->{'dom'}\n";
			}
		print "    Description: $d->{'owner'}\n";
		print "    Username: $d->{'user'}\n";
		print "    Group name: $d->{'group'}\n";
		print "    Mailbox username prefix: $d->{'prefix'}\n";
		print "    Password: $d->{'pass'}\n";
		print "    Home directory: $d->{'home'}\n";
		print "    Contact email: $d->{'emailto'}\n";
		print "    Created on: ",&make_date($d->{'created'}),"\n";
		if ($d->{'creator'}) {
			print "    Created by: $d->{'creator'}\n";
			}
		if ($d->{'disabled'}) {
			$dwhy = $d->{'disabled_reason'} eq 'bw' ?
				  "For exceeding bandwidth limit" :
				$d->{'disabled_why'} ?
				  "Manually ($d->{'disabled_why'})" :
				  "Manually";
			print "    Disabled: $dwhy\n";
			}
		if ($d->{'virt'}) {
			local $iface = &get_address_iface($d->{'ip'});
			print "    IP address: $d->{'ip'} (On $iface)\n";
			}
		else {
			print "    IP address: $d->{'ip'} (Shared)\n";
			}
		print "    Features: ",join(" ", grep { $d->{$_} } @features),"\n";
		if (@feature_plugins) {
			print "    Plugins: ",join(" ", grep { $d->{$_} } @feature_plugins),"\n";
			}
		if (&has_home_quotas() && !$d->{'parent'}) {
			($qhome, $qmail) = &get_domain_quota($d);
			$hs = &quota_bsize("home");
			$ms = &quota_bsize("mail");
			print "    Server quota: ",
			      &quota_show($d->{'quota'}, "home"),"\n";
			print "    Server quota used: ",
			      &nice_size($qhome*$hs + $qmail*$ms),"\n";
			print "    User quota: ",
			      &quota_show($d->{'uquota'}, "home"),"\n";
			print "    User quota used: ",
			      &nice_size($duser->{'uquota'}*$hs +
					 $duser->{'umquota'}*$ms),"\n";
			}
		@dbs = &domain_databases($d);
		if (@dbs) {
			$dbquota = &get_database_usage($d);
			print "    Databases count: ",scalar(@dbs),"\n";
			print "    Databases size: ",&nice_size($dbquota),"\n";
			}
		if ($config{'bw_active'} && !$d->{'parent'}) {
			print "    Bandwidth limit: ",($d->{'bw_limit'} ? &nice_size($d->{'bw_limit'}) : "Unlimited"),"\n";
			if (defined($d->{'bw_usage'})) {
				print "    Bandwidth start: ",&make_date($d->{'bw_start'}*(24*60*60), 1),"\n";
				print "    Bandwidth usage: ",&nice_size($d->{'bw_usage'}),"\n";
				}
			}
		if ($d->{'reseller'}) {
			print "    Reseller: $d->{'reseller'}\n";
			}

		# Show spam and virus delivery
		foreach $w ('spam', 'virus') {
			next if (!$config{$w} || !$d->{$w});
			$func = "get_domain_${w}_delivery";
			($mode, $dest) = &$func($d);
			$msg = $mode == -1 ? "Not configured!" :
			       $mode == 0 ? "Throw away" :
			       $mode == 1 ? "Mail file under home $dest" :
			       $mode == 2 ? "Forward to $dest" :
			       $mode == 3 ? "Mail file $dest" :
			       $mode == 4 ? "Default mail file" :
			       $mode == 5 ? "Deliver normally" :
			       $mode == 6 ? "Default mail directory" :
					    "???";
			print "    ".ucfirst($w)." delivery: $msg\n";
			}

		# Show spam filtering client
		if ($config{'spam'} && $d->{'spam'}) {
			$c = &get_domain_spam_client($d);
			print "    SpamAssassin client: $c\n";
			}

		# Show spam clearing setting
		if ($config{'spam'} && $d->{'spam'}) {
			$auto = &get_domain_spam_autoclear($d);
			print "    Spam clearing policy: ",
			      (!$auto ? "None" :
			       $auto->{'days'} ? "$auto->{'days'} days" :
						 "$auto->{'size'} bytes"),"\n";
			}

		# Show PHP and suexec execution mode
		if ($config{'web'} && $d->{'web'} &&
		    defined(&get_domain_php_mode)) {
			$p = &get_domain_php_mode($d);
			print "    PHP execution mode: $p\n";
			$s = &get_domain_suexec($d);
			print "    SuExec for CGIs: ",
			      ($s ? "enabled" : "disabled"),"\n";
			}

		# Show DNS SPF mode
		if ($config{'dns'} && $d->{'dns'} && !$d->{'dns_submode'}) {
			$spf = &get_domain_spf($d);
			print "    SPF DNS record: ",
			      ($spf ? "Enabled" : "Disabled"),"\n";
			}

		# Show owner limits
		if (!$d->{'parent'}) {
			print "    Maximum sub-servers: ",
			      ($d->{'domslimit'} eq '' ? "Cannot create" :
			       $d->{'domslimit'} eq '*' ? "Unlimited" :
				$d->{'domslimit'}),"\n";
			print "    Maximum alias servers: ",
			      ($d->{'aliasdomslimit'} eq '' ? "Unlimited" :
				$d->{'aliasdomslimit'}),"\n";
			print "    Maximum non-alias servers: ",
			      ($d->{'realdomslimit'} eq '' ? "Unlimited" :
				$d->{'realdomslimit'}),"\n";
			print "    Maximum mailboxes: ",
			      ($d->{'mailboxlimit'} eq '' ? "Unlimited" :
				$d->{'mailboxlimit'}),"\n";
			print "    Maximum databases: ",
			      ($d->{'dbslimit'} eq '' ? "Unlimited" :
				$d->{'dbslimit'}),"\n";
			print "    Maximum aliases: ",
			      ($d->{'aliaslimit'} eq '' ? "Unlimited" :
				$d->{'aliaslimit'}),"\n";
			print "    Can choose database names: ",
				($d->{'nodbname'} ? "No" : "Yes"),"\n";
			print "    Can rename servers: ",
				($d->{'norename'} ? "No" : "Yes"),"\n";
			print "    Sub-servers must be under main domain: ",
				($d->{'forceunder'} ? "Yes" : "No"),"\n";
			print "    Read-only mode: ",
				($d->{'readonly'} ? "Yes" : "No"),"\n";
			print "    Allowed features: ",
				join(" ", grep { $d->{'limit_'.$_} } @allow_features),"\n";
			print "    Edit capabilities: ",
				join(" ", grep { $d->{'edit_'.$_} } @edit_limits),"\n";
			}
		}
	}
else {
	# Just show summary table
	$fmt = "%-30.30s %-15.15s %-30.30s\n";
	printf $fmt, "Domain", "Username", "Description";
	printf $fmt, ("-" x 30), ("-" x 15), ("-" x 30);
	foreach $d (@doms) {
		printf $fmt, $d->{'dom'}, $d->{'user'}, $d->{'owner'};
		}
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Lists the virtual servers on this system.\n";
print "\n";
print "usage: list-domains.pl   [--multiline]\n";
print "                         [--domain name]*\n";
print "                         [--with-feature feature]\n";
print "                         [--without-feature feature]\n";
exit(1);
}


