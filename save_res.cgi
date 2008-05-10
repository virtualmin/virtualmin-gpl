#!/usr/local/bin/perl
# Update memory and process limits

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_res($d) || &error($text{'edit_ecannot'});
&obtain_lock_unix();
&obtain_lock_web($d);

# Validate and store inputs
&error_setup($text{'res_err'});
$rv = &get_domain_resource_limits($d);
if ($in{'procs_def'}) {
	delete($rv->{'procs'});
	}
else {
	$in{'procs'} =~ /^\d+$/ || &error($text{'res_eprocs'});
	$in{'procs'} > 1 || &error($text{'res_eprocs2'});
	$rv->{'procs'} = $in{'procs'};
	}
if ($in{'mem_def'}) {
	delete($rv->{'mem'});
	}
else {
	$in{'mem'} =~ /^\d+$/ || &error($text{'res_emem'});
	$in{'mem'} *= $in{'mem_units'};
	$in{'mem'} > 1024*1024 || &error($text{'res_emem2'});
	$rv->{'mem'} = $in{'mem'};
	}
if ($in{'time_def'}) {
	delete($rv->{'time'});
	}
else {
	$in{'time'} =~ /^\d+$/ || &error($text{'res_etime'});
	$in{'time'} > 0 || &error($text{'res_etime2'});
	$rv->{'time'} = $in{'time'};
	}
&save_domain_resource_limits($d, $rv);

&set_all_null_print();
&run_post_actions();
&release_lock_web($d);
&release_lock_unix();
&webmin_log("res", "domain", $d->{'dom'}, $rv);

&domain_redirect($d);


