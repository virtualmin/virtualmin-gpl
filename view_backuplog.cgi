#!/usr/local/bin/perl
# Show details of one logged backup

require './virtual-server-lib.pl';
&ReadParse();
$in{'id'} =~ /^[0-9\.\-]+$/ || &error($text{'viewbackup_eid'});
$log = &get_backup_log($in{'id'});
$log || &error($text{'viewbackup_egone'});
&can_backup_log($log) || &error($text{'viewbackup_ecannot'});

&ui_print_header(undef, $text{'viewbackup_title'}, "");

# Basic details
print &ui_form_start("restore_form.cgi");
print &ui_hidden("log", $in{'id'});
print &ui_table_start($text{'viewbackup_header'}, "width=100%", 4,
		      [ "nowrap" ]);

# Destination
print &ui_table_row($text{'viewbackup_dest'},
	&nice_backup_url($log->{'dest'}, 1), 3);

# Domains included
@alldnames = split(/\s+/, $log->{'doms'});
@dnames = &backup_log_own_domains($log);
$msg = @alldnames > @dnames ? " , <b>".&text('viewbackup_extra',
					   @alldnames - @dnames)."</b>" : "";
print &ui_table_row($text{'viewbackup_doms'},
	join(" , ", @dnames).$msg || $text{'backuplog_nodoms'}, 3);

# Domains that failed, if any
@errdnames = &backup_log_own_domains($log, 1);
if (@errdnames) {
	print &ui_table_row($text{'viewbackup_errdoms'},
		   "<font color=#ff0000>".join(" , ", @errdnames)."</font>", 3);
	}

# Execution type
print &ui_table_row($text{'viewbackup_mode'},
	$text{'viewbackup_mode_'.$log->{'mode'}});

# By user
print &ui_table_row($text{'viewbackup_user'},
	$log->{'user'} || "<i>$text{'viewbackup_cmd'}</i>");

# Start and end times
print &ui_table_row($text{'viewbackup_start'},
	&make_date($log->{'start'}));
print &ui_table_row($text{'viewbackup_end'},
	&make_date($log->{'end'}));

# Final size
print &ui_table_row($text{'viewbackup_size'},
	&nice_size($log->{'size'}));

# Run time
print &ui_table_row($text{'viewbackup_time'},
	&nice_hour_mins_secs($log->{'end'} - $log->{'start'}));

# Incremental?
print &ui_table_row($text{'viewbackup_inc'},
	$log->{'increment'} == 1 ? $text{'viewbackup_inc1'} :
	$log->{'increment'} == 2 ? $text{'viewbackup_inc2'} :
			    	   $text{'viewbackup_inc0'});

# Final result
print &ui_table_row($text{'viewbackup_ok'},
	$log->{'ok'} && !$log->{'errdoms'} ? $text{'viewbackup_success'} :
	$log->{'ok'} && $log->{'errdoms'} ?
		"<font color=#ffaa00>$text{'viewbackup_partial'}</font>" :
		"<font color=#ff0000>$text{'viewbackup_failure'}</font>");

# Original scheduled backup
if ($log->{'sched'}) {
	($sched) = grep { $_->{'id'} eq $log->{'sched'} }
			&list_scheduled_backups();
	if ($sched) {
		@dests = &get_scheduled_backup_dests($sched);
		@nices = map { &nice_backup_url($_, 1) } @dests;
		print &ui_table_row($text{'viewbackup_sched'},
			&ui_link("backup_form.cgi?sched=".&urlize($log->{'sched'}), $nices[0]), 3);
		}
	else {
		print &ui_table_row($text{'viewbackup_sched'},
				    &text('viewbackup_gone', $log->{'sched'}));
		}
	}

# Encryption key
print &ui_table_row($text{'viewbackup_enc'},
	!$log->{'key'} ? $text{'no'} :
	!defined(&get_backup_key) ?
		"<font color=#ff0000>$text{'viewbackup_nopro'}</font>" :
	!($key = &get_backup_key($log->{'key'})) ?
		"<font color=#ffaa00>".
		  &text('viewbackup_nokey', $log->{'key'})."</font>" :
		&text('viewbackup_key', "<i>$key->{'desc'}</i>"));

print &ui_table_end();

if (@dnames == @alldnames) {
	# Full output
	print &ui_hidden_table_start($text{'viewbackup_output'}, "width=100%",
				     2, "output", $log->{'ok'} ? 0 : 1);
	print &ui_table_row(undef,
		$log->{'mode'} eq 'cgi' ? $log->{'output'} :
			"<pre>".&html_escape($log->{'output'})."</pre>", 2);
	print &ui_hidden_table_end();
	}

if ($log->{'ok'} || $log->{'errdoms'}) {
	print &ui_form_end([ [ undef, $text{'viewbackup_restore'} ] ]);
	}
else {
	print &ui_form_end();
	}

&ui_print_footer("backuplog.cgi?search=".&urlize($in{'search'}),
		 $text{'backuplog_return'});
