#!/usr/local/bin/perl
# Script workbench
# workbench.cgi

use File::Basename;
require './virtual-server-lib.pl';
&ReadParse();
# Checks
&error_setup($text{'scripts_ekit'});
my $d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_scripts() || &error($text{'edit_ecannot'});
&domain_has_website($d) && $d->{'dir'} || &error($text{'scripts_eweb'});
# Get script
my ($sinfo) = grep { $_->{'id'} eq $in{'sid'} } &list_domain_scripts($d);
my $script = &get_script($sinfo->{'name'});
$script || &error($text{'scripts_emissing'});
# Error message
&error("@{[&text('scripts_gpl_pro_tip_workbench_pro_only', $script->{'tmdesc'})]}
        @{[&text('scripts_gpl_pro_tip_enroll_single', $virtualmin_shop_link)]}")
                if (defined($in{'pro'}) && $in{'pro'} ne $virtualmin_pro);
# Run
my $lib = "./pro/scripts/workbench-lib.pl";
do $lib if (-r $lib);
my $apply_func = $script->{'kit_apply_func'};
if (defined(&$apply_func)) {
        &$apply_func($d, \%in, $sinfo, $script);
        }
else {
        &error(&text('scripts_gpl_pro_tip_workbench_pro_only',
                $script->{'tmdesc'}));
        }
