#!/usr/local/bin/perl
# Update frame-forwarding settings

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$oldd = {  %$d };
&can_edit_domain($d) && &can_edit_forward() || &error($text{'edit_ecannot'});

# Validate inputs
&error_setup($text{'frame_err'});
if ($in{'enabled'}) {
	# Activate or update
	$d->{'proxy_pass_mode'} = 2;
	$in{'url'} =~ /^(http|https):\/\/\S+$/ || &error($text{'frame_eurl'});
	$d->{'proxy_pass'} = $in{'url'};
	}
else {
	# Turn off
	$d->{'proxy_pass_mode'} = 0;
	$d->{'proxy_pass'} = undef;
	}
$in{'meta'} =~ s/\r//g;
$in{'meta'} =~ s/\n/\t/g;
$d->{'proxy_title'} = $in{'title'};
$d->{'proxy_meta'} = $in{'meta'};

# Run the before command
&set_domain_envs(\%oldd, "MODIFY_DOMAIN", $d);
$merr = &making_changes();
&reset_domain_envs(\%oldd);
&error(&text('rename_emaking', "<tt>$merr</tt>")) if (defined($merr));

&ui_print_unbuffered_header(&domain_in($d), $text{'frame_title'}, "");

# Call all modify funcs
foreach $f (&list_ordered_features($d)) {
	&call_feature_func($f, $d, $oldd);
	}

if ($in{'enabled'}) {
	# Regenerate frame-forwarding file
	print $text{'frame_gen'},"<br>\n";
	&create_framefwd_file($d);
	print $text{'setup_done'},"<p>\n";
	}

# Save the domain
print $text{'save_domain'},"<br>\n";
&save_domain($d);
print $text{'setup_done'},"<p>\n";

# Run the after command
&run_post_actions();
&set_domain_envs($d, "MODIFY_DOMAIN", undef, \%oldd);
local $merr = &made_changes();
&$second_print(&text('setup_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);
&webmin_log("frame", "domain", $d->{'dom'}, $d);

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});


