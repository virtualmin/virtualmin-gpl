#!/usr/local/bin/perl
# Lists all virtual servers

package virtual_server;
if (!$module_name) {
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
	}

# Parse command-line args
$owner = 1;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--with-feature") {
		$with = shift(@ARGV);
		}
	elsif ($a eq "--without-feature") {
		$without = shift(@ARGV);
		}
	elsif ($a eq "--alias") {
		$must_alias = 1;
		}
	elsif ($a eq "--toplevel") {
		$must_toplevel = 1;
		}
	elsif ($a eq "--subserver") {
		$must_subserver = 1;
		}
	elsif ($a eq "--subdomain") {
		$must_subdomain = 1;
		}
	else {
		&usage();
		}
	}

if (@domains || @users) {
	# Just showing listed domains or domains owned by some user
	@doms = &get_domains_by_names_users(\@domains, \@users, \&usage);
	}
else {
	# Showing all domains, with some limits
	@doms = &list_domains();
	@doms = grep { $_->{'alias'} } @doms if ($must_alias);
	@doms = grep { $_->{'parent'} } @doms if ($must_subserver);
	@doms = grep { !$_->{'parent'} } @doms if ($must_toplevel);
	@doms = grep { $_->{'subdom'} } @doms if ($must_subdomain);
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
	@shells = grep { $_->{'owner'} } &list_available_shells();
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
			print "    Mail aliases mode: ",
				($d->{'aliascopy'} ? "Copy" : "Catchall"),"\n";
			}
		elsif ($d->{'parent'}) {
			$parentdom = &get_domain_by("id", $d->{'parent'});
			print "    Parent domain: $parentdom->{'dom'}\n";
			}
		print "    Description: $d->{'owner'}\n";
		print "    Username: $d->{'user'}\n";
		print "    User ID: $d->{'uid'}\n";
		print "    Group name: $d->{'group'}\n";
		print "    Group ID: $d->{'gid'}\n";
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
			if ($config{'bw_disable'}) {
				print "    Disable if over bandwidth limit: ",
			           ($d->{'bw_no_disable'} ? "No" : "Yes"),"\n";
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
		if ($config{'web'} && $d->{'web'} &&
		    defined(&get_domain_php_children)) {
			$childs = &get_domain_php_children($d);
			print "    PHP fCGId subprocesses: ",
				$childs < 0 ? "Not set" : $childs,"\n";
			}
		if ($config{'web'} && $d->{'web'} &&
		    defined(&get_domain_ruby_mode)) {
			$p = &get_domain_ruby_mode($d) || "none";
			print "    Ruby execution mode: $p\n";
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
			print "    Maximum Mongrel instances: ",
			      ($d->{'mongrelslimit'} eq '' ? "Unlimited" :
				$d->{'mongrelslimit'}),"\n";
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

			($shell) = grep { $_->{'shell'} eq $duser->{'shell'} }
					@shells;
			if ($shell) {
				print "    Shell type: $shell->{'id'}\n";
				print "    Login permissions: $shell->{'desc'}\n";
				}
			print "    Shell command: $duser->{'shell'}\n";
			}

		# Show backup excludes
		if (!$d->{'alias'}) {
			foreach my $e (&get_backup_excludes($d)) {
				print "    Backup exclusion: $e\n";
				}
			}
		}
	}
elsif ($nameonly) {
	# Just names
	foreach $d (@doms) {
		print $d->{'dom'},"\n";
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
print "usage: list-domains.pl   [--multiline | --name-only]\n";
print "                         [--domain name]*\n";
print "                         [--user name]*\n";
print "                         [--with-feature feature]\n";
print "                         [--without-feature feature]\n";
print "                         [--alias | --subserver |\n";
print "                          --toplevel | --subdomain]\n";
exit(1);
}


