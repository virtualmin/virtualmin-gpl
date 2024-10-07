#!/usr/local/bin/perl

=head1 set-dkim.pl

Enable or disable DKIM for all domains.

To enable DKIM signing of outdoing emails, run this command with the
C<--enable> flag. Conversely, to turn it off use the C<--disable>. A default
key size and selector will be used when DKIM is enabled for the first time, 
unless specified with the C<--size> and C<--selector> flags.

By default incoming email will not be checked for a valid DKIM signature
unless the C<--verify> flag is given. To turn off verification, use the 
C<--no-verify> flag instead.

Virtualmin enables DKIM for all virtual servers with email and DNS features, but
you can add extra domains to sign for with the C<--add-dkim> flag followed by a
domain name. Similarly you can remove an extra domain with the C<--remove-extra> flag.

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
	$0 = "$pwd/set-dkim.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "set-spam.pl must be run as root";
	}
@OLDARGV = @ARGV;

&set_all_text_print();

# Parse command-line args
if (@ARGV > 0) {
		while(@ARGV > 0) {
		local $a = shift(@ARGV);
		if ($a eq "--enable") {
			$enabled = 1;
			}
		elsif ($a eq "--disable") {
			$enabled = 0;
			}
		elsif ($a eq "--selector") {
			$selector = shift(@ARGV);
			$selector =~ /^[a-z0-9\.\-\_]+/i || &usage("Invalid selector");
			}
		elsif ($a eq "--size") {
			$size = shift(@ARGV);
			$size =~ /^\d+$/ && $size >= 512 || &usage("Invalid key size");
			}
		elsif ($a eq "--verify") {
			$verify = 1;
			}
		elsif ($a eq "--no-verify") {
			$verify = 0;
			}
		elsif ($a eq "--add-extra") {
			$extra = shift(@ARGV);
			$err = &valid_domain_name($extra);
			$err && &usage("Invalid extra domain name : $err");
			push(@addextra, $extra);
			}
		elsif ($a eq "--remove-extra") {
			$extra = shift(@ARGV);
			push(@delextra, $extra);
			}
		elsif ($a eq "--multiline") {
			$multiline = 1;
			}
		elsif ($a eq "--help") {
			&usage();
			}
		else {
			&usage("Unknown parameter $a");
			}
		}
	}
	else {
		&usage("No parameters given");
		}

# Get current config and update
$dkim = &get_dkim_config();
$dkim ||= { 'selector' => &get_default_dkim_selector(),
	    'sign' => 1, };
$dkim->{'enabled'} = $enabled if (defined($enabled));
$dkim->{'selector'} = $selector if (defined($selector));
$dkim->{'verify'} = $verify if (defined($verify));
foreach my $e (@addextra) {
	push(@{$dkim->{'extra'}}, $e);
	}
foreach my $e (@delextra) {
	$dkim->{'extra'} = [ grep { $_ ne $e } @{$dkim->{'extra'}} ];
	}
$dkim->{'extra'} = [ &unique(@{$dkim->{'extra'}}) ];

if ($dkim->{'enabled'}) {
	# Turn on DKIM, or change settings
        $ok = &enable_dkim($dkim, 0, $size || $dkim->{'size'} || 2048);
        if (!$ok) {
		print "Failed to enable DKIM\n";
                }
        else {
                $config{'dkim_enabled'} = 1;
                }
        }
else {
        # Turn off DKIM
        $ok = &disable_dkim($dkim);
        $config{'dkim_enabled'} = 0;
        }

# Save config if changed
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
&clear_links_cache();

&run_post_actions();
&virtualmin_api_log(\@OLDARGV);

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Enable or disable DKIM for all domains.\n";
print "\n";
print "virtualmin set-dkim [--enable | --disable]\n";
print "                    [--select name]\n";
print "                    [--size bits]\n";
print "                    [--verify | --no-verify]\n";
print "                    [--add-extra domain]*\n";
print "                    [--remove-extra domain]*\n";
exit(1);
}

