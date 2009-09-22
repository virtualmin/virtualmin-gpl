#!/usr/local/bin/perl
# Set the last scanned date for all domains back to the date selected, for
# selected features

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'bwreset_err'});
&can_edit_templates() || &error($text{'newbw_ecannot'});

# Validate inputs
$in{'date_d'} =~ /^\d+$/ || &error($text{'bwreset_eday'});
$in{'date_y'} =~ /^\d{4}$/ || &error($text{'bwreset_eyear'});
$time = eval { timelocal(0, 0, 0, $in{'date_d'}, $in{'date_m'}, $in{'date_y'}-1900) };
$time && !$@ || &error($text{'bwreset_edate'});
$date = $time/(24*60*60);
@features = split(/\0/, $in{'feature'});
@features || &error($text{'bwreset_efeatures'});
if ($in{'domains_def'}) {
	@doms = &list_domains();
	}
else {
	foreach $did (split(/\0/, $in{'domains'})) {
		$d = &get_domain($did);
		push(@doms, $d) if ($d);
		}
	}
@doms || &error($text{'bwreset_edoms'});

&ui_print_header(undef, $text{'bwreset_title'}, "");

# Update all bandwidth files in selected domains
print $text{'bwreset_doing'},"<br>\n";
foreach $d (@doms) {
	$bwinfo = &get_bandwidth($d);
	foreach $f (@features) {
		if ($bwinfo->{'last_'.$f} && $bwinfo->{'last_'.$f} > $time) {
			# Move last-processed time back to the reset point
			$bwinfo->{'last_'.$f} = $time;
			}
		foreach $k (keys %$bwinfo) {
			if ($k =~ /^\Q$f\E_(\d+)$/ && $1 >= $date) {
				$bwinfo->{$k} = 0;
				}
			}
		}
	&save_bandwidth($d, $bwinfo);
	}
print $text{'bwreset_done'},"<p>\n";

# Kick off bw.pl
print $text{'bwreset_running'},"<br>\n";
system("$bw_cron_cmd >/dev/null 2>&1 </dev/null &");
print $text{'bwreset_started'},"<p>\n";

&ui_print_footer("edit_newbw.cgi", $text{'newbw_return'},
		 "", $text{'index_return'});

