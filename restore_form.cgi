#!/usr/local/bin/perl
# Show a form for restoring a single virtual server, or a bunch

require './virtual-server-lib.pl';
&can_backup_domains() || &error($text{'restore_ecannot'});
&ui_print_header(undef, $text{'restore_title'}, "");
&ReadParse();

print &ui_form_start("restore.cgi", "post");
print &ui_table_start($text{'restore_header'}, undef, 2);

# Get source 
$dest = $config{'backup_dest'};
if (defined($in{'dom'})) {
	$d = &get_domain($in{'dom'});
	if ($d->{'backup_dest'}) {
		$dest = $d->{'backup_dest'};
		}
	elsif ($config{'backup_fmt'} == 0 && $dest) {
		$dest .= "/$d->{'dom'}.tar.gz";
		}
	print &ui_hidden("onedom", $d->{'id'}),"\n";
	}

# Show source file field
print &ui_table_row($text{'restore_src'},
		    &show_backup_destination("src", $dest));

# Show feature selection boxes
$ftable = "";
@links = ( &select_all_link("feature"), &select_invert_link("feature") );
$ftable .= &ui_links_row(\@links);
foreach $f (@backup_features) {
	local $bfunc = "restore_$f";
	if (defined(&$bfunc) &&
	    ($config{$f} || $f eq "unix" || $f eq "virtualmin")) {
		$ftable .= &ui_checkbox("feature", $f,
			$text{'backup_feature_'.$f} || $text{'feature_'.$f},
			$config{'backup_feature_'.$f});
		local $ofunc = "show_restore_$f";
		local %opts = map { split(/=/, $_) }
				split(/,/, $config{'backup_opts_'.$f});
		local $ohtml;
		if (defined(&$ofunc) && ($ohtml = &$ofunc(\%opts, $d))) {
			$ftable .= "<table><tr><td>\n";
			$ftable .= ("&nbsp;" x 5);
			$ftable .= "</td> <td>\n";
			$ftable .= $ohtml;
			$ftable .= "</td></tr></table>\n";
			}
		else {
			$ftable .= "<br>\n";
			}
		}
	}
foreach $f (@backup_plugins) {
	$ftable .= &ui_checkbox("feature", $f,
		&plugin_call($f, "feature_backup_name") ||
		    &plugin_call($f, "feature_name"),
		$config{'backup_feature_'.$f})."\n";
	$ftable .= "<br>\n";
	}
$ftable .= &ui_links_row(\@links);
print &ui_table_row($text{'restore_features'}, $ftable);

if (&can_backup_virtualmin() && !defined($in{'dom'})) {
	# Show virtualmin object backup options
	$vtable = "";
	%virts = map { $_, 1 } split(/\s+/, $config{'backup_virtualmin'});
	foreach $vo (@virtualmin_backups) {
		$vtable .= &ui_checkbox("virtualmin", $vo,
				$text{'backup_v'.$vo}, $virts{$vo})."<br>\n";
		}
	print &ui_table_row($text{'restore_virtualmin'}, $vtable);
	}

# Creation options
print &ui_table_row(&hlink($text{'restore_reuid'}, "restore_reuid"),
		    &ui_yesno_radio("reuid", 1));

print &ui_table_row(&hlink($text{'restore_fix'}, "restore_fix"),
		    &ui_yesno_radio("fix", 0));

print &ui_table_end();
print &ui_form_end([ [ "", $text{'restore_now'} ] ]);

&ui_print_footer("", $text{'index_return'});

