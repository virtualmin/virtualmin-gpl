#!/usr/local/bin/perl
# Disables all features in a domain

package virtual_server;
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
if ($0 =~ /^(.*\/)[^\/]+$/) {
	chdir($1);
	}
chop($pwd = `pwd`);
$0 = "$pwd/disable-domain.pl";
require './virtual-server-lib.pl';
$< == 0 || die "disable-domain.pl must be run as root";

$first_print = \&first_text_print;
$second_print = \&second_text_print;

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$domain = lc(shift(@ARGV));
		}
	elsif ($a eq "--why") {
		$why = shift(@ARGV);
		}
	else {
		&usage("Unknown option $a");
		}
	}

# Find the domain
$domain || usage();
$d = &get_domain_by("dom", $domain);
$d || &usage("Virtual server $domain does not exist");
$d->{'disabled'} && &usage("Virtual server $domain is already disabled");

# Work out what can be disabled
@disable = &get_disable_features($d);

# Disable it
print "Disabling virtual server $domain ..\n\n";
%disable = map { $_, 1 } @disable;

# Run the before command
&set_domain_envs($d, "DISABLE_DOMAIN");
$merr = &making_changes();
&reset_domain_envs($d);
&usage(&text('disable_emaking', "<tt>$merr</tt>")) if (defined($merr));

# Disable all configured features
my $f;
foreach $f (@features) {
	if ($d->{$f} && $disable{$f}) {
		local $dfunc = "disable_$f";
		if (&try_function($f, $dfunc, $d)) {
			push(@disabled, $f);
			}
		}
	}
foreach $f (@feature_plugins) {
	if ($d->{$f} && $disable{$f}) {
		&plugin_call($f, "feature_disable", $d);
		push(@disabled, $f);
		}
	}

# Save new domain details
&$first_print($text{'save_domain'});
$d->{'disabled'} = join(",", @disabled);
$d->{'disabled_reason'} = 'manual';
$d->{'disabled_why'} = $why;
&save_domain($d);
&$second_print($text{'setup_done'});

# Run the after command
&run_post_actions();
&set_domain_envs($d, "DISABLE_DOMAIN");
&made_changes();
&reset_domain_envs($d);
print "All done!\n";

sub usage
{
print $_[0],"\n" if ($_[0]);
print "Disables all features in the specified virtual server.\n";
print "\n";
print "usage: disable-domain.pl  --domain domain.name\n";
print "                          [--why \"explanation for disable\"]\n";
exit(1);
}


