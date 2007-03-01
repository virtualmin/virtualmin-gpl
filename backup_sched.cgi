#!/usr/local/bin/perl
# Create, update or delete the backup cron job

require './virtual-server-lib.pl';
&can_backup_domains() || &error($text{'backup_ecannot'});
&ReadParse();

# Validate inputs
&error_setup($text{'backup_err2'});
if ($in{'all'} == 1) {
	@doms = &list_domains();
	}
elsif ($in{'all'} == 2) {
	%exc = map { $_, 1 } split(/\0/, $in{'doms'});
	@doms = grep { !$exc{$_->{'id'}} } &list_domains();
	}
else {
	foreach $d (split(/\0/, $in{'doms'})) {
		push(@doms, &get_domain($d));
		}
	}
@doms || &error($text{'backup_edoms'});
@do_features = split(/\0/, $in{'feature'});
@do_features || &error($text{'backup_efeatures'});
$dest = &parse_backup_destination("dest", \%in);
if ($in{'onebyone'}) {
	$in{'dest_mode'} > 0 || &error($text{'backup_eonebyone1'});
	$in{'fmt'} == 2 || &error($text{'backup_eonebyone2'});
	}

# Parse option inputs
foreach $f (@do_features) {
	local $ofunc = "parse_backup_$f";
	if (&indexof($f, @backup_plugins) < 0 &&
	    defined(&$ofunc)) {
		$options{$f} = &$ofunc(\%in);
		}
	elsif (&indexof($f, @backup_plugins) >= 0 &&
	       &plugin_defined($f, "feature_backup_parse")) {
		$options{$f} = &plugin_call($f, "feature_backup_parse", \%in);
		}
	}

# Parse virtualmin config
if (&can_backup_virtualmin()) {
	@vbs = split(/\0/, $in{'virtualmin'});
	}

# Check if the cron job exists
&foreign_require("cron", "cron-lib.pl");
local @jobs = &cron::list_cron_jobs();
local ($job) = grep { $_->{'user'} eq 'root' &&
		      $_->{'command'} eq $backup_cron_cmd } @jobs;

# Create, update or delete it
if ($job && $in{'enabled'}) {
	# Update job
	&lock_file(&cron::cron_file($job));
	&cron::parse_times_input($job, \%in);
	&cron::change_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	$what = "modify";
	}
elsif (!$job && $in{'enabled'}) {
	# Create job
	$job = { 'user' => 'root',
		 'command' => $backup_cron_cmd,
		 'active' => 1 };
	&lock_file(&cron::cron_file($job));
	&cron::parse_times_input($job, \%in);
	&cron::create_cron_job($job);
	&lock_file($backup_cron_cmd);
	&cron::create_wrapper($backup_cron_cmd, $module_name, "backup.pl");
	&unlock_file($backup_cron_cmd);
	&unlock_file(&cron::cron_file($job));
	$what = "create";
	}
elsif ($job && !$in{'enabled'}) {
	# Delete job
	&lock_file(&cron::cron_file($job));
	&cron::delete_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	$what = "delete";
	}
else {
	$what = "none";
	}

# Update module config with domains and features
$config{'backup_all'} = $in{'all'};
$config{'backup_doms'} = join(" ", split(/\0/, $in{'doms'}));
%features = map { $_, 1 } @do_features;
foreach $f (@backup_features, @backup_plugins) {
	$config{'backup_feature_'.$f} = $features{$f} ? 1 : 0;
	}
$config{'backup_dest'} = $dest;
$config{'backup_fmt'} = $in{'fmt'};
$config{'backup_mkdir'} = $in{'mkdir'};
$config{'backup_email'} = $in{'email'};
$config{'backup_errors'} = $in{'errors'};
$config{'backup_strftime'} = $in{'strftime'};
$config{'backup_onebyone'} = $in{'onebyone'};
$config{'last_check'} = time()+1;	# no need for check.cgi to be run
foreach $f (keys %options) {
	$config{'backup_opts_'.$f} = join(",", map { $_."=".$options{$f}->{$_} } keys %{$options{$f}});
	}
if (defined(@vbs)) {
	$config{'backup_virtualmin'} = join(" ", @vbs);
	}
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
&webmin_log("sched", $what);

# Show nice confirmation page
&ui_print_header(undef, $text{'backup_title2'}, "");

if ($in{'enabled'}) {
	print &text($in{'all'} == 1 ? 'backup_senabled1' : 'backup_senabled0',
		    scalar(@doms)),"<p>\n";
	}
else {
	print $text{'backup_sdisabled'},"<p>\n";
	}

&ui_print_footer("", $text{'index_return'});
