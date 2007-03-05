#!/usr/local/bin/perl
# Update dynamic IP settings

require './virtual-server-lib.pl';
&error_setup($text{'newdynip_err'});
&ReadParse();
&can_edit_templates() || &error($text{'newdynip_ecannot'});

# Validate inputs
if ($in{'enabled'}) {
	$in{'host'} =~ /^[a-z0-9\.\-\_]+$/ || &error($text{'newdynip_ehost'});
	$in{'email_def'} || $in{'email'} =~ /\S/ ||
		&error($text{'newdynip_eemail'});
	}

# Save them
$config{'dynip_service'} = $in{'service'};
$config{'dynip_host'} = $in{'host'};
$config{'dynip_auto'} = $in{'auto'};
$config{'dynip_user'} = $in{'duser'};
$config{'dynip_pass'} = $in{'dpass'};
$config{'dynip_email'} = $in{'email_def'} ? undef : $in{'email'};
&save_module_config();
$job = &get_dynip_cron_job();
if ($in{'enabled'} && !$job) {
	# Need to create
	$job = { 'command' => $dynip_cron_cmd,
		 'user' => 'root',
		 'mins' => '0,5,10,15,20,25,30,35,40,45,50,55',
		 'hours' => '*',
		 'days' => '*',
		 'months' => '*',
		 'weekdays' => '*',
		 'active' => 1 };
	&lock_file(&cron::cron_file($job));
	&cron::create_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	&cron::create_wrapper($dynip_cron_cmd, $module_name, "dynip.pl");
	}
elsif (!$in{'enabled'} && $job) {
	# Need to delete
	&lock_file(&cron::cron_file($job));
	&cron::delete_cron_job($job);
	&unlock_file(&cron::cron_file($job));
	}
&webmin_log("dynip");

# Tell the user
&ui_print_header(undef, $text{'newdynip_title'}, "");

if ($in{'enabled'}) {
	$ip = $in{'auto'} ? &get_external_ip_address() : &get_default_ip();
	print &text('newdynip_on', "<tt>$ip</tt>"),"<p>\n";
	}
else {
	print $text{'newdynip_off'},"<p>\n";
	}

&ui_print_footer("", $text{'index_return'});

