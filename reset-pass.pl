#!/usr/local/bin/perl

=head1 reset-pass.pl

Resets the password for some or all users in some or all virtual servers.

This command can be used to mass update the passwords of all users in a
virtual server, or just those matching some criteria. For example, to
reset the password for all users in the domain example.com, run :

  virtualmin reset-pass --domain example.com

To update the password for just the user joe in example.com, run :

  virtualmin reset-pass --domain example.com --user joe

To update the password for all users in all domains, run :

  virtualmin reset-pass --all-domains

To update the password for all users in all domains except the owners, run :

  virtualmin reset-pass --all-domains --exclude-owner

All passwords will be set to a random value, unless the C<--pass> flag is
given, in which case the same password will be used for all users.

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
	$0 = "$pwd/reset-pass.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "reset-pass.pl must be run as root";
	}

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all = 1;
		}
	elsif ($a eq "--exclude-owner") {
		$exclude_owner = 1;
		}
	elsif ($a eq "--user") {
		$usernames{shift(@ARGV)} = 1;
		}
    elsif ($a eq "--pass") {
		$pass = shift(@ARGV);
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Parse args and get domains
@dnames || $all || &usage("No domains or users specified");
if ($all) {
	@doms = &list_domains();
	}
else {
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}

# Change the password
foreach my $d (@doms) {
	my @users = &list_domain_users($d, 0, 0, 0, 0);
    my @users_users = grep { !$_->{'domainowner'} } @users;
    my @users_owners = grep { $_->{'domainowner'} } @users;
	if (%usernames) {
		@users_users = grep { $usernames{$_->{'user'}} ||
				$usernames{&remove_userdom($_->{'user'}, $d)} }
			      @users_users;
        @users_owners = grep { $usernames{$_->{'user'}} ||
				$usernames{&remove_userdom($_->{'user'}, $d)} }
			      @users_owners;
		}
    #
    my $dom_done;
    #
    print "Updating user passwords in domain $d->{'dom'} ..\n";
    #
    if (!$exclude_owner) {
        @users_owners = map { $_->{'user'} } @users_owners;
        foreach my $user (@users_owners) {
            $dom_done++;
            my $passwd = $pass || &random_password();
            my $oldd = $d;
            if ($d->{'disabled'}) {
                $d->{'disabled_mysqlpass'} = undef;
                $d->{'disabled_postgrespass'} = undef;
                }
            $d->{'pass'} = $passwd;
            $d->{'pass_set'} = 1;
            #
            &push_all_print();
            &set_all_null_print();
            eval {
                &generate_domain_password_hashes($d, 0);
                &modify_unix($d, $oldd) if ($d->{'unix'});
                &modify_webmin($d, $oldd);
                &save_domain($d);
                };
            &pop_all_print();
            if ($@) {
                print "  Failed to set new password for owner \"$user\" user\n";
                }
            else {
                print "  Updated owner user \"$user\" with password \"$passwd\"\n";
                }
            }
        }
    #
    @users_users = map { $_->{'user'} } @users_users;
    foreach my $user (@users_users) {
        $dom_done++;        
        my ($u) = grep { $_->{'user'} eq $user } @users;
        my $oldu = $u;
        my $passwd = $pass || &random_password();
        #
        &push_all_print();
        &set_all_null_print();
        eval {
            $u->{'passmode'} = 3;
            $u->{'plainpass'} = $passwd;
            $u->{'pass'} = &encrypt_user_password($u, $passwd);
            &set_pass_change($u);
            &set_usermin_imap_password($u);
            &modify_user($u, $oldu, $d);
            };
        &pop_all_print();
        if ($@) {
            print "  Failed to set new password for \"$user\" user\n";
            }
        else {
            print "  Updated user \"$user\" with password \"$passwd\"\n";
            }
        }
    #
    if ($dom_done) {
        print ".. done\n";
        }
    else {
        print ".. no users found with given criteria\n";
        }
	}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Resets the password for some or all users in some or all virtual servers.\n";
print "\n";
print "virtualmin reset-pass --all-domains | --domain name\n";
print "                     [--exclude-owner]\n";
print "                     [--user name]\n";
print "                     [--pass]\n";
exit(1);
}
