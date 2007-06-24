#!/usr/local/bin/perl
# Restart some feature-related service

require './virtual-server-lib.pl';
&ReadParse();
&can_stop_servers() || &error($text{'restart_ecannot'});
if (&indexof($in{'feature'}, @plugins) < 0) {
	# Core feature
	$startfunc = "start_service_".$in{'feature'};
	$stopfunc = "stop_service_".$in{'feature'};
	$err = &$stopfunc();
	if (!$err) {
		$err = &$startfunc();
		}
	$name = $text{'feature_'.$in{'feature'}};
	}
else {
	# Plugin
	$err = &plugin_call($in{'feature'}, "feature_stop_service");
	if (!$err) {
		$err = &plugin_call($in{'feature'}, "feature_start_service");
		}
	$name = &plugin_call($in{'feature'}, "feature_name");
	}
&error_setup($text{'restart_err'});
&error($err) if ($err);
&refresh_startstop_status();
&webmin_log("restart", $in{'feature'});

if ($in{'show'}) {
	# Tell the user
	&ui_print_header(undef, $text{'restart_title'}, "");

	print &text('restart_done', $name),"<p>\n";

	&ui_print_footer("", $text{'index_return'});
	}
elsif ($in{'redirect'}) {
	&redirect($in{'redirect'});
	}
else {
	&redirect($ENV{'HTTP_REFERER'});
	}


