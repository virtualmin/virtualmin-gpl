#!/usr/local/bin/perl

=head1 list-users.pl

List users in a virtual server

To get a list of users associated with some virtual server, this program can
be used. You should typically supply the C<--domain> parameter, which must be followed by the domain name of the server to list users for. This can be given
several times, to display users from more than one domain. Or use 
C<--all-domains> to list users from all virtual servers on the system. Finally,
users from domains owned by a particular user can be listed with the
C<--domain-user> flag, which must be followed by an administrator's username.

By default, it will output a
reader-friendly table of users, but you can use the C<--multiline> option to show
more detail in a format that is suitable for reading by other programs. To
just show the usernames, use the C<--name-only> flag. Or to list all email
addresses for all users, use the C<--email-only> flag.

By default the server owner is not included in the list of users, but if you
add the C<--include-owner> command line option, he will be. Also by default the
size of each user's mail file is now shown in the multiline mode output, as
computing it can be disk-intensive. To display the mail file / directory size,
add the C<--mail-size> flag.

To limit the display to just one user in the domain, add the C<--user>
parameter to the command line, followed by a full or short username.

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
	$0 = "$pwd/list-users.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-users.pl must be run as root";
	}

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
	elsif ($a eq "--name-only") {
		$nameonly = 1;
		}
	elsif ($a eq "--email-only") {
		$emailonly = 1;
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
	elsif ($a eq "--simple-aliases") {
		$simplemode = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Parse args and get domains
@dnames || @users || $all || &usage("No domains or users specified");
if ($all) {
	@doms = &list_domains();
	}
else {
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}
@ashells = grep { $_->{'mailbox'} } &list_available_shells();

foreach $d (@doms) {
	@users = &list_domain_users($d, $owner, 0, 0, 0);
	if (%usernames) {
		@users = grep { $usernames{$_->{'user'}} ||
				$usernames{&remove_userdom($_->{'user'}, $d)} }
			      @users;
		}
	if ($multi) {
		# Show attributes on separate lines
		$home_bsize = &has_home_quotas() ? &quota_bsize("home") : 0;
		$mail_bsize = &has_mail_quotas() ? &quota_bsize("mail") : 0;
		foreach $u (@users) {
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
			($shell) = grep { $_->{'shell'} eq $u->{'shell'} }
					@ashells;
			print "    FTP access: ",
			    ($shell->{'id'} eq 'nologin' ? "No" : "Yes"),"\n";
			if ($shell) {
				print "    Login permissions: ",
				      $shell->{'desc'},"\n";
				}
			print "    Shell: ",$u->{'shell'},"\n";
			print "    User type: ",
				($u->{'domainowner'} ? "Server owner" :
				 $u->{'webowner'} ? "Website manager" :
						    "Normal user"),"\n";
			if ($u->{'mailquota'}) {
				print "    Mail server quota: ",
				      $u->{'qquota'},"\n";
				}
			if ($u->{'unix'} && &has_home_quotas() &&
			    !$u->{'noquota'}) {
				print "    Home quota: ",
				      &quota_show($u->{'quota'}, "home"),"\n";
				print "    Home quota used: ",
				      &quota_show($u->{'uquota'}, "home"),"\n";
				print "    Home byte quota: ",
				      ($u->{'quota'} * $home_bsize),"\n";
				print "    Home byte quota used: ",
				      ($u->{'uquota'} * $home_bsize),"\n";
				}
			if ($u->{'unix'} && &has_mail_quotas() &&
			    !$u->{'noquota'}) {
				print "    Mail quota: ",
				      &quota_show($u->{'mquota'}, "mail"),"\n";
				print "    Mail quota used: ",
				      &quota_show($u->{'umquota'}, "mail"),"\n";
				print "    Mail byte quota: ",
				      ($u->{'mquota'} * $mail_bsize),"\n";
				print "    Mail byte quota used: ",
				      ($u->{'umquota'} * $mail_bsize),"\n";
				}
			if ($mailsize) {
				($msize) = &mail_file_size($u);
				print "    Mail file size: ",
				      &nice_size($msize),"\n";
				print "    Mail file byte size: ",
				      $msize,"\n";
				}
			($mfile, $mtype) = &user_mail_file($u);
			print "    Mail location: $mfile\n";
			print "    Mail storage type: ",
			      ($mtype == 0 ? "mbox" : $mtype == 1 ? "Maildir" :
			       "Type $mtype"),"\n";
			if ($u->{'email'}) {
				print "    Email address: ",
				      $u->{'email'},"\n";
				}
			if (@{$u->{'extraemail'}} && !$u->{'noextra'}) {
				print "    Extra addresses: ",
				      join(" ", @{$u->{'extraemail'}}),"\n";
				}
			if ($config{'spam'}) {
				print "    Check spam and viruses: ",
					!$d->{'spam'} ? "Disabled for domain" :
					$u->{'nospam'} ? "No" : "Yes","\n";
				}
			$ll = &get_last_login_time($u->{'user'});
			if ($ll) {
				print "    Last logins: ",
				    join(", ",
				       map { $_." ".&make_date($ll->{$_}) }
					   keys %$ll),"\n";
				}
			@dblist = ( );
			foreach $db (@{$u->{'dbs'}}) {
				push(@dblist, $db->{'name'}." ($db->{'type'})");
				}
			if (@dblist) {
				print "    Databases: ",
				      join(", ", @dblist),"\n";
				}
			if (@{$u->{'secs'}}) {
				print "    Secondary groups: ",
				      join(" ", @{$u->{'secs'}}),"\n";
				}

			if ($u->{'noalias'}) {
				# Nothing to show for forwarding
				}
			elsif ($simplemode) {
				# Show simple forwarding
				$simple = @{$u->{'to'}} ?
				   &get_simple_alias($d, $u) : { 'tome' => 1 };
				print "    Deliver to user: ",
				      ($simple->{'tome'} ? "Yes" : "No"),"\n";
				foreach $f (@{$simple->{'forward'}}) {
					print "    Forward: $f\n";
					}
				if ($simple->{'auto'}) {
					$msg = $simple->{'autotext'};
					$msg =~ s/\n/\\n/g;
					print "    Autoreply message: $msg\n";
					}
				if ($simple->{'autoreply_start'}) {
					print "    Autoreply start: ",
					      &time_to_date($simple->{'autoreply_start'})."\n";
					}
				if ($simple->{'autoreply_end'}) {
					print "    Autoreply end: ",
					      &time_to_date($simple->{'autoreply_end'})."\n";
					}
				if ($simple->{'period'}) {
					print "    Autoreply period: ",
					      "$simple->{'period'}\n";
					}
				if ($simple->{'from'}) {
					print "    Autoreply from: ",
					      "$simple->{'from'}\n";
					}
				}
			else {
				# Show basic forwards
				foreach $t (@{$u->{'to'}}) {
					print "    Forward mail to: $t\n";
					}
				}
			}
		}
	elsif ($nameonly) {
		# Just show full usernames
		foreach $u (@users) {
			print $u->{'user'},"\n";
			}
		}
	elsif ($emailonly) {
		# Just show addresses, where they exist
		foreach $u (@users) {
			print $u->{'email'},"\n" if ($u->{'email'});
			foreach $e (@{$u->{'extraemail'}}) {
				print $e,"\n";
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
			($shell) = grep { $_->{'shell'} eq $u->{'shell'} }
					@ashells;
			printf $fmt, &remove_userdom($u->{'user'}, $d),
				    $u->{'real'},
				    $u->{'email'} ? "Yes" : "No",
				    $shell->{'id'} eq 'nologin' ? "No" : "Yes",
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
print "virtualmin list-users --all-domains | --domain name | --domain-user username\n";
print "                     [--multiline | --name-only | --email-only]\n";
print "                     [--include-owner]\n";
print "                     [--user name]\n";
print "                     [--simple-aliases]\n";
exit(1);
}

