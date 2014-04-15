#!/usr/local/bin/perl

=head1 modify-php-ini.pl

Changes PHP variables for some or all domains.

This command can be used to change the value of a PHP configuration variable
(set in the php.ini file and Apache configuration) for one or many virtual
servers at once. The servers to update can be selected with the C<--domain> or
C<--user> flags, or you can choose to modify them all with the C<--all-domains>
option.

If your system supports multiple PHP versions, you can limit the changes
to the config for a specific version with the C<--php-version> flag folowed
by a number, like 4 or 5.

The variables to change are set with the C<--ini-name> flag, which can be
given multiple times to change more than one variable. The new values are
set either with the C<--ini-value> flag (followed by a number or string),
or the C<--no-ini-value> flag to completely remove a setting.

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
	$0 = "$pwd/modify-php-ini.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "modify-php-ini.pl must be run as root";
	}
&foreign_require("phpini", "phpini-lib.pl");
@OLDARGV = @ARGV;
&set_all_text_print();

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		push(@domains, shift(@ARGV));
		}
	elsif ($a eq "--user") {
		push(@users, shift(@ARGV));
		}
	elsif ($a eq "--all-domains") {
		$all_doms = 1;
		}
	elsif ($a eq "--ini-name") {
		push(@ini_names, shift(@ARGV));
		}
	elsif ($a eq "--ini-value") {
		push(@ini_values, shift(@ARGV));
		}
	elsif ($a eq "--no-ini-value") {
		push(@ini_values, undef);
		}
	elsif ($a eq "--php-version") {
		$php_ver = shift(@ARGV);
		}
	elsif ($a eq "--multiline") {
		$multiline = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Validate parameters
@domains || @users || $all_doms || usage("No domains to modify specified");
@ini_names || &usage("The --ini-name parameter must be given at least once");
@ini_names == @ini_values ||
	&usage("The number of names and values must be the same");

# Get the domains
if (@domains || @users) {
	@doms = &get_domains_by_names_users(\@domains, \@users, \&usage);
	}
else {
	@doms = &list_domains();
	}

# Do each domain
foreach my $d (@doms) {
	# Check if we can manage this domain
	&$first_print("Updating $d->{'dom'} ..");
	if (!&domain_has_website($d) || $d->{'alias'}) {
		&$second_print(".. no website enabled");
		next;
		}

	# Update php.ini files
	$mode = &get_domain_php_mode($d);
	if ($mode ne "mod_php") {
		# Get the ini files
		@inis = &list_domain_php_inis($d);
		if ($php_ver) {
			@inis = grep { $_->[0] == $php_ver } @inis;
			if (!@inis) {
				&$second_print(".. no PHP configuration for ".
					       "version $php_ver found");
				next;
				}
			}

		# Update settings in each one
		foreach $ini (@inis) {
			&lock_file($ini->[1]);
			$conf = &phpini::get_config($ini->[1]);
			for(my $i=0; $i<@ini_names; $i++) {
				&phpini::save_directive($conf, $ini_names[$i],
							       $ini_values[$i]);
				}
			&flush_file_lines($ini->[1], undef, 1);
			&unlock_file($ini->[1]);
			}
		}

	# Update Apache PHP directives
	$mod_php = 0;
	if ($d->{'web'} && ($apache::httpd_modules{'mod_php4'} ||
			    $apache::httpd_modules{'mod_php5'})) {
		&obtain_lock_web($d);
		local @ports;
		push(@ports, $d->{'web_port'}) if ($d->{'web'});
		push(@ports, $d->{'web_sslport'}) if ($d->{'ssl'});
		foreach my $port (@ports) {
			local ($virt, $vconf, $conf) = &get_apache_virtual(
							$d->{'dom'}, $port);
			next if (!$virt);

			# Find currently set PHP variables
			local @phpv = &apache::find_directive(
					"php_value", $vconf);
			for(my $i=0; $i<@ini_names; $i++) {
				my $found = 0;
				for(my $j=0; $j<@phpv; $j++) {
					if ($phpv[$j] =~ /^(\S+)\s/ &&
					    $1 eq $ini_names[$i]) {
						$phpv[$j] = $ini_names[$i]." ".
							    $ini_values[$i];
						$found = 1;
						last;
						}
					}
				if (!$found) {
					push(@phpv, $ini_names[$i]." ".
						    $ini_values[$i]);
					}
				}
			&apache::save_directive("php_value",
						\@phpv, $vconf, $conf);
			&flush_file_lines($virt->{'file'});
			&release_lock_web($d);
			&register_post_action(\&restart_apache);
			$mod_php = 1;
			}
		}

	&$second_print(".. updated ",scalar(@ini_names)," variables in ",
		       scalar(@inis)," files",
		       ($mod_php ? " and Apache configuration" : ""));
	}

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Changes PHP variables for some or all domains.\n";
print "\n";
print "virtualmin modify-php-ini --domain name | --user name | --all-domains\n";
print "                         [--php-version number]\n";
print "                         <--ini-name name>+ <--ini-value value>+\n";
exit(1);
}
