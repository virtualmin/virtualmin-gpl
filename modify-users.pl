#!/usr/local/bin/perl

=head1 modify-users.pl

Modify attributes of some or all users for some or all virtual servers.

This command can be used to mass update attributes of all users C<--all-users>
in all existing virtual servers C<--all-domains> in one shot.

This command essentially acts as a wrapper for the C<virtualmin modify-user>
subprogram. For more details, please check its help documentation.

For example, to enable email for all users in all domains, run :

  virtualmin modify-users --all-domains --all-users --enable-email

To disable email for all users in the given domain, run :

  virtualmin modify-users --domain example.com --all-users --disable-email

To modify quota for all joe users in all domains, run :

  virtualmin modify-users --all-domains --user joe --quota UNLIMITED

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
	$0 = "$pwd/modify-users.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-users.pl must be run as root";
	}
&licence_status();

# Parse command-line args
my $argvs = "@ARGV";
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--all-domains") {
		$all_doms = 1;
		}
  elsif ($a eq "--domain") {
		push(@dnames, shift(@ARGV));
        $domain = 1;
		}
	elsif ($a eq "--all-users") {
		$all_users = 1;
		}
  elsif ($a eq "--user") {
        $usernames{shift(@ARGV)} = 1;
        $user = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	}

# Prepare argvs string for subprogram
$argvs =~ s/--domain\s+(?:(?!--)(\S+))//;
$argvs =~ s/--domain(?!\w)//;
$argvs =~ s/--user\s+(?:(?!--)(\S+))//;
$argvs =~ s/--user(?!\w)//;
$argvs =~ s/--all-domains//;
$argvs =~ s/--all-users//;
$argvs = &trim($argvs);

# Sanity check for args in this program
if (!$all_doms && !$domain) {
    &usage("No --domain or --all-domains flag given");
    }
elsif (!$all_users && !$user) {
    &usage("No --user or --all-users flag given");
    }
elsif ($argvs !~ /\S/) {
    &usage("No additional auxiliary subcommand parameters given");
    }

# Parse args and get domains
if ($all_doms) {
	@doms = &list_domains();
	}
else {
	@doms = &get_domains_by_names_users(\@dnames, \@users, \&usage);
	}

# Run the subcommand for given domains and users
foreach my $d (@doms) {
	my @users = &list_domain_users($d, 0, 0, 0, 0);
	if (%usernames) {
		@users = grep { $usernames{$_->{'user'}} ||
				$usernames{&remove_userdom($_->{'user'}, $d)} }
			      @users;
		}
    my $dom_done;
    #
    print "Updating user attributes in domain $d->{'dom'} ..\n";
    foreach my $user (map { $_->{'user'} } @users) {
        $dom_done++;
        # Run subcommand
        my $ex = &execute_command("virtualmin modify-user --domain @{[quotemeta($d->{'dom'})]} --user @{[$user]} $argvs", undef, \$out);

        my ($out_before_new_empty_line) = $out =~ /(.*?)(?:\n\s*\n|\z)/;
        my $out_ = &trim($out_before_new_empty_line || $out);
        # Prep helpers
        $out_ =~ s/(the\suser(?!\w))/$1 $user/ig;
        $out_ =~ s/(the\sdomain(?!\w))/$1 $d->{'dom'}/ig;
        if ($ex) {
                print "  Failed: $out_\n";
            }
        else {
                print "  Done: $out_\n";
            }
        }
    #
    if ($dom_done) {
        print ".. done\n";
        }
    else {
        print ".. no users in domain found with given criteria\n";
        }
	}

sub usage
{
my $help_modify_user;
&execute_command("virtualmin modify-user --help", undef, \$help_modify_user);
# Clear everything before modify-user
$help_modify_user =~ s/(?s)(.*?)(?=virtualmin\s+modify-user)//;
# Clear modify-user, --domain and --user lines and
# return the rest if it was a part of this help text
$help_modify_user =~ s/virtualmin\s+modify-user\s+--domain\s+domain\.name.*[\r\n]+\s+--user\s+username//;
# This modify-users help text is indented by 24 spaces
my $spaces = ' ' x 24;
$help_modify_user =~ s/^\s+/$spaces/gm;
print "$_[0]\n\n" if ($_[0]);
print "Modify attributes of some or all users for some or all virtual servers.\n";
print "\n";
# Print specific help text to this wrapper
print "virtualmin modify-users --all-domains | --domain name\n";
print "                        --all-users | --user name\n";
# Print modify-user subprogram help text
print $help_modify_user;
exit(1);
}
