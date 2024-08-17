#!/usr/local/bin/perl
# Perform login to script

require './virtual-server-lib.pl';
&ReadParse();
my $d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
my ($sinfo) = grep { $_->{'id'} eq $in{'sid'} } &list_domain_scripts($d);
$sinfo || &error($text{'scripts_emissing'});
my $script = &get_script($sinfo->{'name'});
$script || &error($text{'scripts_emissing'});
# If defined scripts login function
my $kit_login_func = $script->{'kit_login_func'};
if (defined(&$kit_login_func)) {
        # Call script login function
        my $scall = $in{'scall'} ? &convert_from_json($in{'scall'}) : undef;
        $kit_login_func->($d, $script, $sinfo, $scall, \%in);
        # Redirect to script login page
        return;
        }
