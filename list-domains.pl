#!/usr/local/bin/perl

=head1 list-domains.pl

Lists all virtual servers.

This program does not modify the system, but instead simply outputs a list of
all existing virtual servers. By default, the list is a reader-friendly
format, but the C<--multiline> option can be used to display more details for
each server, in a format suitable for parsing by other programs. The C<--domain>
option can be used to specify a single virtual server to list, in cases where
you know exactly which server you are interested in.

To limit the domains to those owned by a single user, the C<--user> parameter
can be given, following by a domain owner's name. You can also limit it to
particular server types with the C<--alias>, C<--no-alias>, C<--subserver>,
C<--toplevel> and C<--subdomain> parameters.

To only show domains with a particular feature
active, use the C<--with-feature> parameter followed by a feature code like
C<dns> or C<web>. Alternately, C<--without-feature> can be used to show
only domains without some feature enabled. The similar C<--with-web> and
C<--with-ssl> flags can be used to show domains with any kind of website
(Apache or Nginx).

To limit the list to virtual servers on some plan, use the C<--plan> flag
followed by a plan name or ID. Similarly, you can select only virtual servers
created using some template with the C<--template> flag, followed by an ID
or name.

To show only domains owned by some reseller, use the C<--reseller> flag followed
by a reseller name. Or to list those not owned by any reseller, use the
C<--no-reseller> flag. Finally, to list domains owned by any reseller, you
can use the C<--any-reseller> option.

To show only domains that are enabled, use the C<--enabled> flag. To show
only disabled domains, use C<--disabled> instead.

To find the domain that contains a mailbox, use the C<--mail-user> flag
followed by the full mailbox username (as used by FTP and IMAP).

To get a list of domain names only, use the C<--name-only> parameter. To get
just Virtualmin domain IDs, use C<--id-only>. These are useful when iterating
through domains in a script. You can also use C<--user-only> to output only
usernames, or C<--home-only> to get just home directories, or 
C<--simple-multiline> to get a faster subset of the information output in
C<--multiline> mode.

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
	$0 = "$pwd/list-domains.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-domains.pl must be run as root";
	}
&require_mail();

# Parse command-line args
$owner = 1;
@allplans = &list_plans();
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--multiline") {
		$multi = 1;
		}
	elsif ($a eq "--simple-multiline") {
		$multi = 2;
		}
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--id-only") {
		$idonly = 1;
		}
	elsif ($a eq "--user-only") {
		$useronly = 1;
		}
	elsif ($a eq "--home-only") {
		$homeonly = 1;
		}
	elsif ($a eq "--file-only") {
		$fileonly = 1;
		}
	elsif ($a eq "--ip-only") {
		$iponly = 1;
		}
	elsif ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--mail-user") {
		push(@mailusers, shift(@ARGV));
		}
	elsif ($a eq "--id") {
		push(@ids, shift(@ARGV));
		}
	elsif ($a eq "--with-feature") {
		$with = shift(@ARGV);
		}
	elsif ($a eq "--without-feature") {
		$without = shift(@ARGV);
		}
	elsif ($a eq "--with-web") {
		$withweb = 1;
		}
	elsif ($a eq "--with-ssl") {
		$withssl = 1;
		}
	elsif ($a eq "--alias") {
		$must_alias = 1;
		if (@ARGV && $ARGV[0] !~ /^-/) {
			$aliasof = shift(@ARGV);
			}
		}
	elsif ($a eq "--no-alias") {
		$must_noalias = 1;
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
	elsif ($a eq "--parent") {
		$parentof = shift(@ARGV);
		}
	elsif ($a eq "--plan") {
		$planname = shift(@ARGV);
		($plan) = grep { lc($_->{'name'}) eq lc($planname) ||
				 $_->{'id'} eq $planname } @allplans;
		$plan || &usage("No plan with name or ID $planname found");
		push(@plans, $plan);
		}
	elsif ($a eq "--template") {
		$tmplid = shift(@ARGV);
		$must_tmpl = &get_template($tmplid);
		if (!$must_tmpl) {
			($must_tmpl) = grep { $_->{'name'} eq $tmplid }
					    &list_templates();
			}
		$must_tmpl ||
			&usage("No template with ID or name $planid was found");
		}
	elsif ($a eq "--reseller") {
		$resel = shift(@ARGV);
		}
	elsif ($a eq "--no-reseller") {
		$no_resel = 1;
		}
	elsif ($a eq "--any-reseller") {
		$any_resel = 1;
		}
	elsif ($a eq "--disabled") { $disabled = 1; }
	elsif ($a eq "--enabled") { $disabled = 0; }
	else {
		&usage("Unknown parameter $a");
		}
	}

if (@ids) {
	# Get domains by IDs
	foreach $id (@ids) {
		$d = &get_domain($id);
		$d || &usage("No virtual server with ID $id exists");
		push(@doms, $d);
		}
	}
elsif (@domains || @users || @plans) {
	# Just showing listed domains or domains owned by some user
	@doms = &get_domains_by_names_users(\@domains, \@users, \&usage,
					    \@plans);
	}
elsif (@mailusers) {
	# Get domains by mailboxes in them
	my %done;
	foreach my $u (@mailusers) {
		$d = &get_user_domain($u);
		if ($d && !$done{$d->{'id'}}++) {
			push(@doms, $d);
			}
		}
	}
else {
	# Showing all domains, with some limits
	@doms = &list_domains();
	}

# Get alias/parent domains
if ($aliasof) {
	$aliasofdom = &get_domain_by("dom", $aliasof);
	$aliasofdom || &usage("No alias target named $aliasof found");
	}
if ($parentof) {
	$parentofdom = &get_domain_by("dom", $parentof);
	$parentofdom || &usage("No parent named $parentof found");
	}

@doms = grep { $_->{'alias'} } @doms if ($must_alias);
@doms = grep { !$_->{'alias'} } @doms if ($must_noalias);
@doms = grep { $_->{'parent'} } @doms if ($must_subserver);
@doms = grep { !$_->{'parent'} } @doms if ($must_toplevel);
@doms = grep { $_->{'subdom'} } @doms if ($must_subdomain);
@doms = sort { $a->{'user'} cmp $b->{'user'} ||
	       $a->{'created'} <=> $b->{'created'} } @doms;
if ($aliasofdom) {
	@doms = grep { $_->{'alias'} eq $aliasofdom->{'id'} } @doms;
	}
if ($parentofdom) {
	@doms = grep { $_->{'parent'} eq $parentofdom->{'id'} } @doms;
	}

# Limit to those with/without some feature
if ($with) {
	@doms = grep { $_->{$with} } @doms;
	}
if ($withweb) {
	@doms = grep { &domain_has_website($_) } @doms;
	}
if ($withssl) {
	@doms = grep { &domain_has_ssl($_) } @doms;
	}
if ($without) {
	@doms = grep { !$_->{$without} } @doms;
	}

# Limit to those on some template
if ($must_tmpl) {
	@doms = grep { $_->{'template'} eq $must_tmpl->{'id'} } @doms;
	}

# Limit by reseller
if ($resel) {
	@doms = grep { &indexof($resel, split(/\s+/, $_->{'reseller'})) >= 0 }
		     @doms;
	}
elsif ($no_resel) {
	@doms = grep { !$_->{'reseller'} } @doms;
	}
elsif ($any_resel) {
	@doms = grep { $_->{'reseller'} } @doms;
	}

# Limit by enabled status
if ($disabled eq '1') {
	@doms = grep { $_->{'disabled'} } @doms;
	}
elsif ($disabled eq '0') {
	@doms = grep { !$_->{'disabled'} } @doms;
	}

if ($multi) {
	# Show attributes on multiple lines
	@shells = grep { $_->{'owner'} } &list_available_shells();
	$resok = defined(&supports_resource_limits) &&
		 &supports_resource_limits();
	@tmpls = &list_templates();
	@fplugins = &list_feature_plugins();
	if ($multi == 1) {
		$hs = &quota_bsize("home");
		$ms = &quota_bsize("mail");
		$sender_bcc = &get_all_domains_sender_bcc();
		$recipient_bcc = &get_all_domains_recipient_bcc();
		}
	foreach $d (@doms) {
		local @users = &list_domain_users($d, 0, 1, 0, 1);
		local ($duser) = grep { $_->{'user'} eq $d->{'user'} } @users;
		print "$d->{'dom'}\n";
		print "    ID: $d->{'id'}\n";
		print "    File: $d->{'file'}\n";
		print "    Type: ",($d->{'alias'} && $d->{'aliasmail'} ?
					"Alias with own email" :
				    $d->{'alias'} ? "Alias" :
				    $d->{'parent'} ? "Sub-server" :
						     "Top-level server"),"\n";
		$dname = &show_domain_name($d, 2);
		if ($dname ne $d->{'dom'}) {
			print "    International domain name: $dname\n";
			}
		if (&domain_has_website($d)) {
			print "    URL: ",&get_domain_url($d),"/\n";
			}
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
		if ($d->{'linkdom'}) {
			$linkdom = &get_domain($d->{'linkdom'});
			print "    Domain for links: $linkdom->{'dom'}\n"
				if ($linkdom);
			}
		print "    Description: $d->{'owner'}\n";
		print "    Template ID: $d->{'template'}\n";
		($tmpl) = grep { $_->{'id'} eq $d->{'template'} } @tmpls;
		if ($tmpl) {
			print "    Template: $tmpl->{'name'}\n";
			}
		print "    Plan ID: $d->{'plan'}\n";
		$plan = &get_plan($d->{'plan'});
		if ($plan) {
			print "    Plan: $plan->{'name'}\n";
			}
		print "    Username: $d->{'user'}\n";
		print "    User ID: $d->{'uid'}\n";
		print "    Group name: $d->{'group'}\n";
		print "    Group ID: $d->{'gid'}\n";
		print "    Mailbox username prefix: $d->{'prefix'}\n";
		print "    Password storage: ",
		      ($d->{'hashpass'} ? "Hashed" : "Plain text"),"\n";
		if ($d->{'pass'}) {
			print "    Password: $d->{'pass'}\n";
			}
		elsif ($d->{'enc_pass'}) {
			print "    Hashed password: $d->{'enc_pass'}\n";
			}
		foreach my $f (grep { $d->{$_} } @database_features) {
			my $ufunc = "${f}_user";
			if (defined(&$ufunc)) {
				my $u = &$ufunc($d, 1);
				print "    Username for ${f}: $u\n";
				}
			my $pfunc = "${f}_pass";
			if (defined(&$pfunc)) {
				my $p = &$pfunc($d, 1);
				print "    Password for ${f}: $p\n";
				}
			}
		if ($d->{'mysql'} && $d->{'mysql_module'} ne 'mysql') {
			my $host = &get_database_host_mysql($d);
			print "    Hostname for mysql: $host\n";
			}
		print "    Home directory: $d->{'home'}\n";
		if (!$d->{'parent'} && ($jail = &get_domain_jailkit($d))) {
			print "    Jail directory: $jail\n";
			}
		if (&domain_has_website($d)) {
			$wd = $d->{'alias'} ? &get_domain($d->{'alias'}) : $d;
			print "    HTML directory: ",&public_html_dir($wd),"\n";
			print "    CGI directory: ",&cgi_bin_dir($wd),"\n";
			print "    Access log: ",&get_website_log($wd, 0),"\n";
			print "    Error log: ",&get_website_log($wd, 1),"\n";
			}
		print "    Contact email: $d->{'emailto'}\n";
		print "    Contact address: $d->{'emailto_addr'}\n";
		print "    Created on: ",&make_date($d->{'created'}),"\n";
		print "    Created Unix time: ",$d->{'created'},"\n";
		if ($d->{'creator'}) {
			print "    Created by: $d->{'creator'}\n";
			}
		if ($d->{'disabled'}) {
			$dwhy = $d->{'disabled_reason'} eq 'bw' ?
				  "For exceeding bandwidth limit" :
				$d->{'disabled_reason'} eq 'transfer' ?
				  "Transferred to another system" :
				$d->{'disabled_why'} ?
				  "Manually ($d->{'disabled_why'})" :
				  "Manually";
			print "    Disabled: $dwhy\n";
			if ($d->{'disabled_time'}) {
				print "    Disabled at: ",
				      &make_date($d->{'disabled_time'}),"\n";
				}
			}
		if ($d->{'virt'}) {
			if ($multi == 2) {
				print "    IP address: $d->{'ip'} (Private)\n";
				}
			else {
				local $iface = &get_address_iface($d->{'ip'});
				print "    IP address: $d->{'ip'} ",
				      "(On $iface)\n";
				}
			}
		else {
			print "    IP address: $d->{'ip'} (Shared)\n";
			}
		if ($d->{'virt6'}) {
			if ($multi == 2) {
				print "    IP address: $d->{'ip6'} (Private)\n";
				}
			else {
				local $iface = &get_address_iface($d->{'ip6'});
				print "    IP address: $d->{'ip6'} ",
				      "(On $iface)\n";
				}
			}
		elsif ($d->{'ip6'}) {
			print "    IPv6 address: $d->{'ip6'}\n";
			}
		if ($d->{'dns_ip'}) {
			print "    External IP address: $d->{'dns_ip'}\n";
			}
		print "    Features: ",
			join(" ", grep { $d->{$_} } @features),"\n";
		print "    Plugins: ",
			join(" ", grep { $d->{$_} } @fplugins),"\n";
		@rfeatures = &list_remote_domain_features($d);
		if (@rfeatures) {
			print "    Remote features: ",
				join(" ", @rfeatures),"\n";
			}
		if (&has_home_quotas() && !$d->{'parent'}) {
			print "    Server quota: ",
			      &quota_show($d->{'quota'}, "home"),"\n";
			print "    Server block quota: ",
			      ($d->{'quota'} || "Unlimited"),"\n";
			if ($multi == 1) {
				($qhome, $qmail) = &get_domain_quota($d);
				print "    Server quota used: ",
				      &nice_size($qhome*$hs + $qmail*$ms),"\n";
				print "    Server block quota used: ",
				      ($qhome + $qmail),"\n";
				print "    Server byte quota used: ",
				      ($qhome*$hs + $qmail*$ms),"\n";
				}
			print "    User quota: ",
			      &quota_show($d->{'uquota'}, "home"),"\n";
			print "    User block quota: ",
			      ($d->{'uquota'} || "Unlimited"),"\n";
			if ($multi == 1) {
				print "    User quota used: ",
				      &nice_size($duser->{'uquota'}*$hs +
						 $duser->{'umquota'}*$ms),"\n";
				print "    User block quota used: ",
				      ($duser->{'uquota'} +
				       $duser->{'umquota'}),"\n";
				print "    User byte quota used: ",
				      ($duser->{'uquota'}*$hs +
				       $duser->{'umquota'}*$ms),"\n";
				}
			}
		if ($multi == 1) {
			@dbs = &domain_databases($d);
			if (@dbs) {
				$dbquota = &get_database_usage($d);
				print "    Databases count: ",
				      scalar(@dbs),"\n";
				print "    Databases size: ",
				      &nice_size($dbquota),"\n";
				print "    Databases byte size: ",
				      $dbquota,"\n";
				}
			}
		if ($config{'bw_active'} && !$d->{'parent'}) {
			print "    Bandwidth limit: ",
			    ($d->{'bw_limit'} ? &nice_size($d->{'bw_limit'})
					      : "Unlimited"),"\n";
			print "    Bandwidth byte limit: ",
			    ($d->{'bw_limit'} || "Unlimited"),"\n";
			if (defined($d->{'bw_usage'})) {
				print "    Bandwidth start: ",
				    &make_date($d->{'bw_start'}*(24*60*60), 1),
				    "\n";
				print "    Bandwidth usage: ",
				      &nice_size($d->{'bw_usage'}),"\n";
				print "    Bandwidth byte usage: ",
				      ($d->{'bw_usage'}),"\n";
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
		if ($multi == 1) {
			foreach $w ('spam', 'virus') {
				next if (!$config{$w} || !$d->{$w});
				$func = "get_domain_${w}_delivery";
				($mode, $dest, $slevel) = &$func($d);
				$msg = $mode == -1 ? "Not configured!" :
				       $mode == 0 ? "Throw away" :
				       $mode == 1 ? "Mail file under home $dest" :
				       $mode == 2 ? "Forward to $dest" :
				       $mode == 3 ? "Mail file $dest" :
				       $mode == 4 ? "Default mail file $dest" :
				       $mode == 5 ? "Deliver normally" :
				       $mode == 6 ? "Default mail directory $dest" :
						    "???";
				print "    ".ucfirst($w)." delivery: $msg\n";
				if ($w eq 'spam' && $slevel) {
					print "    Spam deletion level: ",
					      "$slevel\n";
					}
				}
			}

		# Show spam filtering client
		if ($config{'spam'} && $d->{'spam'} && $multi == 1) {
			$c = &get_domain_spam_client($d);
			print "    SpamAssassin client: $c\n";
			}

		# Show spam clearing setting
		if ($config{'spam'} && $d->{'spam'} && $multi == 1) {
			$auto = &get_domain_spam_autoclear($d);
			print "    Spam clearing policy: ",
			  ($auto->{'days'} ? "$auto->{'days'} days" :
			   $auto->{'size'} ? "$auto->{'size'} bytes" :
					     "None"),"\n";
			print "    Trash clearing policy: ",
			  ($auto->{'trashdays'} ? "$auto->{'trashdays'} days" :
			   $auto->{'trashsize'} ? "$auto->{'trashsize'} bytes" :
						  "None"),"\n";
			}

		# Show PHP and suexec execution mode
		if (!$d->{'alias'} &&
		    &domain_has_website($d) && $multi == 1) {
			$p = &get_domain_php_mode($d);
			print "    PHP execution mode: $p\n";
			@modes = &supported_php_modes($d);
			print "    Possible PHP execution modes: ",
				join(" ", @modes),"\n";
			$s = &get_domain_suexec($d);
			print "    SuExec for CGIs: ",
			      ($s ? "enabled" : "disabled"),"\n";
			}
		if (!$d->{'alias'} &&
		    &domain_has_website($d) &&
		    defined(&get_domain_php_children) && $multi == 1) {
			$childs = &get_domain_php_children($d);
			print "    PHP fCGId subprocesses: ",
				$childs < 0 ? "Not set" :
				$childs == 0 ? "None" : $childs,"\n";
			}
		$p = &domain_has_website($d);
		if (!$d->{'alias'} &&
		    ($p eq 'web' ||
		     &plugin_defined($p, "feature_get_fcgid_max_execution_time"))) {
			$max = $mode eq "fcgid" ?
				&get_fcgid_max_execution_time($d) :
				&get_php_max_execution_time($d);
			print "    PHP max execution time: ",
			      ($max || "Unlimited"),"\n";
			}
		if (!$d->{'alias'} &&
		    &domain_has_website($d) &&
		    defined(&list_domain_php_directories) && $multi == 1) {
			($dir) = &list_domain_php_directories($d);
			if ($dir) {
				print "    PHP version: $dir->{'version'}\n";
				}
			}
		if (!$d->{'alias'} &&
		    &domain_has_website($d) &&
		    defined(&get_domain_ruby_mode) && $multi == 1) {
			$p = &get_domain_ruby_mode($d) || "none";
			print "    Ruby execution mode: $p\n";
			}

		# Show webmail redirects
		if (!$d->{'alias'} &&
		    &has_webmail_rewrite($d) && &domain_has_website($d) &&
		    !$d->{'alias'} && $multi == 1) {
			@wm = &get_webmail_redirect_directives($d);
			print "    Webmail redirects: ",
				(@wm ? "Yes" : "No"),"\n";
			}

		# Show star web server alias
		if (&domain_has_website($d) && !$d->{'alias'} && $multi == 1) {
			$star = &get_domain_web_star($d);
			print "    Match all web sub-domains: ",
			      ($star ? "Yes" : "No"),"\n";
			}

		# Shiw SSI setting
		if (&domain_has_website($d) && !$d->{'alias'} && $multi == 1) {
			($ssi, $suffix) = &get_domain_web_ssi($d);
			print "    Server-side includes: ",
			      ($ssi == 0 ? "Disabled" : 
			       $ssi == 1 ? "Enabled for $suffix" :
					   "Global default"),"\n";
			}

		# Show default website flag
		if (&domain_has_website($d) && $multi == 1 &&
		    (!$d->{'alias'} || $d->{'alias_mode'} != 1)) {
			print "    Default website for IP: ",
				(&is_default_website($d) ? "Yes" : "No"),"\n";
			}

		# Show SSL cert
		if ($d->{'ssl_key'}) {
			print "    SSL key file: $d->{'ssl_key'}\n";
			}
		if ($d->{'ssl_cert'}) {
			print "    SSL cert file: $d->{'ssl_cert'}\n";
			}
		if ($d->{'ssl_chain'}) {
			print "    SSL CA file: $d->{'ssl_chain'}\n";
			}
		$same = $d->{'ssl_same'} ? &get_domain($d->{'ssl_same'})
					 : undef;
		if ($same) {
			print "    SSL shared with: $same->{'dom'}\n";
			}
		if ($multi == 1) {
			@sslhn = &get_hostnames_for_ssl($d);
			print "    SSL candidate hostnames: ",
				join(" ", @sslhn),"\n";
			}
		if ($d->{'ssl_cert_expiry'}) {
			print "    SSL cert expiry: ",
			    &make_date($d->{'ssl_cert_expiry'}),"\n";
			}
		if ($d->{'letsencrypt_renew'} || $d->{'letsencrypt_last'}) {
			print "    Lets Encrypt renewal: ",
			    ($d->{'letsencrypt_renew'} ? "Enabled"
						       : "Disabled"),"\n";
			}
		if ($d->{'letsencrypt_last'}) {
			print "    Lets Encrypt cert issued: ",
			    &make_date($d->{'letsencrypt_last'}),"\n";
			}
		if ($d->{'letsencrypt_dname'}) {
			print "    Lets Encrypt domain: ",
			    $d->{'letsencrypt_dname'},"\n";
			}

		# Show SSL cert usage by other services
		if ($multi == 1) {
			foreach my $svc (&get_all_domain_service_ssl_certs($d)) {
				print "    SSL cert used by: ",
				      $svc->{'id'},
				      ($svc->{'dom'} ? " ($svc->{'dom'})" :
				       $svc->{'ip'} ? " ($svc->{'ip'})" : ""),
				      "\n";
				}
			}

		# Show provisioned features
		foreach my $f (&list_provision_features()) {
			my $mode = "Local";
			if ($d->{'provision_'.$f}) {
				$mode = "Cloudmin Services";
				}
			elsif ($f eq "dns" && $d->{'dns_cloud'}) {
				my ($cloud) = grep { $_->{'name'} eq
					$d->{'dns_cloud'} } &list_dns_clouds();
				$mode = "Cloud DNS Provider $cloud->{'desc'}";
				}
			print "    Provisioning for ${f}: $mode\n";
			}

		# Show DNS SPF mode
		if ($config{'dns'} && $d->{'dns'} && !$d->{'dns_submode'} &&
		    $multi == 1) {
			$spf = &is_domain_spf_enabled($d);
			print "    SPF DNS record: ",
			      ($spf ? "Enabled" : "Disabled"),"\n";
			$dmarc = &is_domain_dmarc_enabled($d);
			print "    DMARC DNS record: ",
			      ($dmarc ? "Enabled" : "Disabled"),"\n";
			}

		# Slave DNS servers
		if ($config{'dns'} && $d->{'dns'} && $d->{'dns_slave'}) {
			print "    Slave DNS servers: ",
			      $d->{'dns_slave'},"\n";
			}

		# Containing DNS domain
		if ($d->{'dns_submode'}) {
			$dnsparent = &get_domain($d->{'dns_subof'});
			print "    Parent DNS virtual server: ",$dnsparent->{'dom'},"\n";
			}

		# DNS registrar expiry date
		if ($d->{'whois_expiry'}) {
			print "    DNS expiry date: ",
				&make_date($d->{'whois_expiry'}, 1),"\n";
			}

		# Show BCC setting
		$bcc = $sender_bcc->{$d->{'id'}};
		if ($bcc) {
			print "    BCC email to: $bcc\n";
			}
		$rbcc = &get_domain_recipient_bcc($d);
		if ($rbcc) {
			print "    BCC incoming email to: $rbcc\n";
			}

		# Show cloud mail setting
		if ($config{'mail'} && $d->{'mail'} && $multi == 1) {
			if ($d->{'cloud_mail_provider'}) {
				print "    Cloud mail filter: ",
				      $d->{'cloud_mail_provider'},"\n";
				}
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
			print "    Can migrate backups: ",
				($d->{'migrate'} ? "Yes" : "No"),"\n";
			print "    Sub-servers must be under main domain: ",
				($d->{'forceunder'} ? "Yes" : "No"),"\n";
			print "    Sub-servers cannot be under other domains: ",
				($d->{'safeunder'} ? "Yes" : "No"),"\n";
			print "    Sub-servers inherit IP address: ",
				($d->{'ipfollow'} ? "Yes" : "No"),"\n";
			print "    Read-only mode: ",
				($d->{'readonly'} ? "Yes" : "No"),"\n";
			print "    Allowed features: ",
				join(" ", grep { $d->{'limit_'.$_} }
					       &list_allowable_features()),"\n";
			print "    Edit capabilities: ",
				join(" ", grep { $d->{'edit_'.$_} }
					       @edit_limits),"\n";
			print "    Allowed scripts: ",
				($d->{'allowedscripts'} || "All"),"\n";

			$shellcmd = &get_domain_shell($d);
			($shell) = grep { $_->{'shell'} eq $shellcmd }
					@shells;
			if ($shell) {
				print "    Shell type: $shell->{'id'}\n";
				print "    Login permissions: ",
				      "$shell->{'desc'}\n";
				}
			print "    Shell command: $shellcmd\n";
			}

		# Show resource limits
		if (!$d->{'parent'} && $resok && $multi == 1) {
			$rv = &get_domain_resource_limits($d);
			print "    Maximum processes: ",
				$rv->{'procs'} || "Unlimited","\n";
			print "    Maximum size per process: ",
				$rv->{'mem'} ? &nice_size($rv->{'mem'})
					     : "Unlimited","\n";
			print "    Maximum CPU time per process: ",
				$rv->{'time'} ? $rv->{'time'}." mins"
					      : "Unlimited","\n";
			}

		# Show backup excludes
		if (!$d->{'alias'}) {
			foreach my $e (&get_backup_excludes($d)) {
				print "    Backup exclusion: $e\n";
				}
			foreach my $e (&get_backup_db_excludes($d)) {
				print "    Backup DB exclusion: $e\n";
				}
			}

		# Show allowed DB hosts
		if (!$d->{'parent'} && $multi == 1) {
			foreach $f (grep { $config{$_} &&
					   $d->{$_} } @database_features) {
				$gfunc = "get_".$f."_allowed_hosts";
				if (defined(&$gfunc)) {
					@hosts = &$gfunc($d);
					print "    Allowed $f hosts: ",
					      join(" ", @hosts),"\n";
					}
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
elsif ($idonly) {
	# Just IDs
	foreach $d (@doms) {
		print $d->{'id'},"\n";
		}
	}
elsif ($useronly) {
	# Just usernames
	foreach $d (@doms) {
		print $d->{'user'},"\n";
		}
	}
elsif ($homeonly) {
	# Just home directories
	foreach $d (@doms) {
		print $d->{'home'},"\n";
		}
	}
elsif ($fileonly) {
	# Just domain files
	foreach $d (@doms) {
		print $d->{'file'},"\n";
		}
	}
elsif ($iponly) {
	# Just IP addresses
	foreach $d (@doms) {
		print $d->{'ip'},"\n";
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
print "virtualmin list-domains [--multiline | --name-only | --id-only |\n";
print "                         --simple-multiline | --user-only |\n";
print "                         --home-only | --file-only | --ip-only]\n";
print "                        [--domain name]*\n";
print "                        [--user name]*\n";
print "                        [--mail-user name]*\n";
print "                        [--id number]*\n";
print "                        [--with-feature feature]\n";
print "                        [--without-feature feature]\n";
print "                        [--with-web] [--with-ssl]\n";
print "                        [--alias domain | --no-alias]\n";
print "                        [--subserver | --toplevel | --subdomain]\n";
print "                        [--parent domain]\n";
print "                        [--plan ID|name]\n";
print "                        [--template ID|name]\n";
print "                        [--disabled | --enabled]\n";
if ($virtualmin_pro) {
	print "                        [--reseller name | --no-reseller |\n";
	print "                         --any-reseller]\n";
	}
exit(1);
}


