#!/usr/local/bin/perl
# Start some feature-related service

require './virtual-server-lib.pl';
&ReadParse();
&can_stop_servers() || &error($text{'start_ecannot'});
if (&indexof($in{'feature'}, @plugins) < 0) {
	# Core feature
	$sfunc = "start_service_".$in{'feature'};
	$err = &$sfunc();
	$name = $text{'feature_'.$in{'feature'}};
	}
else {
	# Plugin
	$err = &plugin_call($in{'feature'}, "feature_start_service");
	$name = &plugin_call($in{'feature'}, "feature_name");
	}
&error_setup($text{'start_err'});
&refresh_startstop_status();
&error($err) if ($err);
&webmin_log("start", $in{'feature'});

if ($in{'show'}) {
	# Tell the user
	&ui_print_header(undef, $text{'start_title'}, "");

	print &text('start_done', $name),"<p>\n";

	&run_post_actions();

	&ui_print_footer("", $text{'index_return'});
	}
elsif ($in{'redirect'}) {
	&run_post_actions_silently();
	&redirect($in{'redirect'});
	}
else {
	&run_post_actions_silently();
	&redirect($ENV{'HTTP_REFERER'});
	}


