#!/usr/local/bin/perl
# Update proxying settings

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$oldd = {  %$d };
&can_edit_domain($d) && &can_edit_forward() || &error($text{'edit_ecannot'});

# Validate inputs
&error_setup($text{'proxy_err'});
if ($in{'enabled'}) {
	# Activate or update
	$d->{'proxy_pass_mode'} = 1;
	$in{'url'} =~ /^(http|https):\/\/\S+$/ || &error($text{'frame_eurl'});
	if ($in{'url'} =~ /(http|https):\/\/[^\/]+$/) {
		# Add trailing / if URL is like http://foo.com
		$in{'url'} .= "/";
		}
	$d->{'proxy_pass'} = $in{'url'};
	}
else {
	# Turn off
	$d->{'proxy_pass_mode'} = 0;
	$d->{'proxy_pass'} = undef;
	}

# Run the before command
&set_domain_envs(\%oldd, "MODIFY_DOMAIN", $d);
$merr = &making_changes();
&reset_domain_envs(\%oldd);
&error(&text('rename_emaking', "<tt>$merr</tt>")) if (defined($merr));

&ui_print_unbuffered_header(&domain_in($d), $text{'proxy_title'}, "");

# Call all modify funcs
foreach $f (&list_ordered_features($d)) {
	&call_feature_func($f, $d, $oldd);
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
&webmin_log("proxy", "domain", $d->{'dom'}, $d);

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});


