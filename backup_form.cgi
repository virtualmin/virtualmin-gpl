#!/usr/local/bin/perl
# Show a form for backing up a single virtual server, or a bunch

require './virtual-server-lib.pl';
&ReadParse();

if ($in{'sched'}) {
	&ui_print_header(undef, $text{'backup_title2'}, "");
	print &ui_form_start("backup_sched.cgi", "post");
	print &ui_table_start($text{'backup_header2'}, undef, 2);
	}
else {
	&ui_print_header(undef, $text{'backup_title'}, "");
	print &ui_form_start("backup.cgi", "post");
	print &ui_table_start($text{'backup_header'}, undef, 2);
	}

# Work out default backup selection
$dest = $config{'backup_dest'};
$backup_fmt = $config{'backup_fmt'};
$backup_mkdir = $config{'backup_mkdir'};
$backup_errors = $config{'backup_errors'};
$backup_strftime = $config{'backup_strftime'};
$backup_onebyone = $config{'backup_onebyone'};
if (defined($in{'dom'})) {
	# Just one domain
	$d = &get_domain($in{'dom'});
	($cbmode = &can_backup_domain($d)) || &error($text{'backup_ecannot'});
	if (defined($d->{'backup_dest'})) {
		$dest = $d->{'backup_dest'};
		}
	elsif ($config{'backup_fmt'} == 0 && $dest) {
		$dest .= "/$d->{'dom'}.tar.gz";
		}
	$backup_fmt = $d->{'backup_fmt'}
		if (defined($d->{'backup_fmt'}));
	$backup_mkdir = $d->{'backup_mkdir'}
		if (defined($d->{'backup_mkdir'}));
	$backup_errors = $d->{'backup_errors'}
		if (defined($d->{'backup_errors'}));
	$backup_strftime = $d->{'backup_strftime'}
		if (defined($d->{'backup_strftime'}));
	$backup_onebyone = $d->{'backup_onebyone'}
		if (defined($d->{'backup_onebyone'}));
	print &ui_hidden("dom", $in{'dom'}),"\n";
	print &ui_hidden("doms", $in{'dom'}),"\n";
	print &ui_hidden("backup_all", 0),"\n";
	print &ui_table_row(&hlink($text{'backup_doms'}, "backup_doms"),
			    "<tt>$d->{'dom'}</tt>");
	}
else {
	# User can select which domains
	($cbmode = &can_backup_domain()) || &error($text{'backup_ecannot'});
	$backup_all = int($config{'backup_all'});
	@bak = split(/\s+/, $config{'backup_doms'});
	@doms = &list_domains();
	$dsel = &ui_radio("all", $backup_all,
			[ [ 1, $text{'backup_all'} ],
			  [ 0, $text{'backup_sel'} ],
			  [ 2, $text{'backup_exc'} ] ])."<br>\n".
		&servers_input("doms", \@bak, \@doms);
	print &ui_table_row(&hlink($text{'backup_doms'}, "backup_doms"),
			    $dsel);
	}

# Show feature and plugin selection boxes
$ftable = "";
@links = ( &select_all_link("feature"), &select_invert_link("feature") );
$ftable .= &ui_links_row(\@links);
foreach $f (@backup_features) {
	local $bfunc = "backup_$f";
	if (defined(&$bfunc) &&
	    ($config{$f} || $f eq "unix" || $f eq "virtualmin")) {
		$ftable .= &ui_checkbox("feature", $f,
			$text{'backup_feature_'.$f} || $text{'feature_'.$f},
			$config{'backup_feature_'.$f})."\n";
		local $ofunc = "show_backup_$f";
		if (defined(&$ofunc)) {
			local %opts = map { split(/=/, $_) }
					 split(/,/, $config{'backup_opts_'.$f});
			$ftable .= &$ofunc(\%opts);
			}
		$ftable .= "<br>\n";
		}
	}
foreach $f (@backup_plugins) {
	$ftable .= &ui_checkbox("feature", $f,
		&plugin_call($f, "feature_backup_name") ||
		    &plugin_call($f, "feature_name"),
		$config{'backup_feature_'.$f})."\n";
	if (&plugin_defined($f, "feature_backup_opts")) {
		local %opts = map { split(/=/, $_) }
				 split(/,/, $config{'backup_opts_'.$f});
		$ftable .= &plugin_call($f, "feature_backup_opts", \%opts);
		}
	$ftable .= "<br>\n";
	}
$ftable .= &ui_links_row(\@links);
print &ui_table_row(&hlink($text{'backup_features'}, "backup_features"),
		    $ftable);

if (&can_backup_virtualmin() && !defined($in{'dom'})) {
	# Show virtualmin object backup options
	$vtable = "";
	%virts = map { $_, 1 } split(/\s+/, $config{'backup_virtualmin'});
	foreach $vo (@virtualmin_backups) {
		$vtable .= &ui_checkbox("virtualmin", $vo,
				$text{'backup_v'.$vo}, $virts{$vo})."<br>\n";
		}
	print &ui_table_row(&hlink($text{'backup_virtualmin'},
				   "backup_virtualmin"), $vtable);
	}

# Show destination fields
print &ui_table_row(&hlink($text{'backup_dest'}, "backup_dest"),
	    &show_backup_destination("dest", $dest, $cbmode == 2, $d)."\n".
	    &ui_checkbox("strftime", 1,
			 &hlink($text{'backup_strftime'}, "backup_strftime"),
			 $backup_strftime)."<br>\n".
	    ($d ? "" :
	      &ui_checkbox("onebyone", 1,
			   &hlink($text{'backup_onebyone'}, "backup_onebyone"),
			   $backup_onebyone)));

# Single/multiple file mode
if (!$d) {
	print &ui_table_row(&hlink($text{'backup_fmt'}, "backup_fmt"),
		&ui_radio("fmt", int($backup_fmt),
			  [ [ 0, $text{'backup_fmt0'} ],
			    [ 1, $text{'backup_fmt1'} ],
			    [ 2, $text{'backup_fmt2'} ] ])."<br>".
		&ui_checkbox("mkdir", 1, $text{'backup_mkdir'},
			     int($backup_mkdir)));
	}
elsif ($cbmode == 1) {
	print &ui_table_row(&hlink($text{'backup_mkdir'}, "backup_mkdir"),
		&ui_yesno_radio("mkdir", int($backup_mkdir)));
	}

# Show error mode
print &ui_table_row(&hlink($text{'backup_errors'}, "backup_errors"),
		    &ui_radio("errors", int($backup_errors),
			      [ [ 0, $text{'backup_errors0'} ],
				[ 1, $text{'backup_errors1'} ] ]));

if ($in{'sched'}) {
	# Show schedule inputs
	&foreign_require("cron", "cron-lib.pl");
	local @jobs = &cron::list_cron_jobs();
	local ($job) = grep { $_->{'user'} eq 'root' &&
			      $_->{'command'} eq $backup_cron_cmd } @jobs;

	# Enabled/disabled input
	print &ui_table_row(&hlink($text{'backup_enabled'}, "backup_enabled"),
			    &ui_radio("enabled", $job ? 1 : 0,
				[ [ 0, $text{'no'} ],
				  [ 1, $text{'backup_enabledyes'} ] ]));

	# Email input
	print &ui_table_row(&hlink($text{'backup_email'}, "backup_email"),
			    &ui_textbox("email", $config{'backup_email'}, 40));

	# Times input
	print "<tr> <td colspan=2><table border>\n";
	$job ||= { 'special' => 'daily' };
	&cron::show_times_input($job);
	print "</table></td> </tr>\n";

	print &ui_table_end();
	print &ui_form_end([ [ "save", $text{'backup_save'} ] ]);
	}
else {
	print &ui_table_end();
	print &ui_form_end([ [ "now", $text{'backup_now'} ] ]);
	}

&ui_print_footer("", $text{'index_return'});

