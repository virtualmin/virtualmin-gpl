#!/usr/local/bin/perl
# Show logs of backups this user has permissions on

require './virtual-server-lib.pl';
&ReadParse();
&can_backup_log() || &error($text{'backuplg_ecannot'});
&ui_print_header(undef, $text{'backuplog_title'}, "");

# Show search form
print &ui_form_start("backuplog.cgi");
print "<b>$text{'backuplog_search'}</b>\n";
print &ui_textbox("search", $in{'search'}, 30);
print &ui_submit($text{'backuplog_ok'});
print &ui_form_end(),"<p>\n";

# Get backups to list
$days = $config{'backuplog_days'} || 7;
@logs = &list_backup_logs($in{'search'} ? undef : time()-24*60*60*$days);
if ($in{'search'}) {
	@logs = grep { $_->{'user'} eq $in{'search'} ||
		       $_->{'doms'} =~ /\Q$in{'search'}\E/i ||
		       $_->{'dest'} =~ /\Q$in{'search'}\E/i } @logs;
	}
$anylogs = scalar(@logs);
@logs = grep { &can_backup_log($_) } @logs;

# Tell the user what he is searching for
if ($in{'search'}) {
	print &text('backuplog_match',
		    "<i>".&html_escape($in{'search'})."</i>"),"<br>\n";
	}
else {
	print &text('backuplog_days', $days),"<br>\n";
	}

if (@logs) {
	# Show in a table
	@table = ( );
	foreach $log (sort { $b->{'start'} <=> $a->{'start'} } @logs) {
		@dnames = &backup_log_own_domains($log);
		next if (!@dnames);
		$ddesc = scalar(@dnames) == 0 ?
				$text{'backuplog_nodoms'} :
			 scalar(@dnames) <= 2 ?
				join(", ", @dnames) :
				&text('backuplog_doms', scalar(@dnames));
		push(@table, [
			"<a href='view_backuplog.cgi?id=".&urlize($log->{'id'}).
			 "&search=".&urlize($in{'search'})."'>".
			 &nice_backup_url($log->{'dest'}, 1)."</a>",
			$ddesc,
		        $log->{'user'} || "<i>root</i>",
			&make_date($log->{'start'}),
			&short_nice_hour_mins_secs(
				$log->{'end'} - $log->{'start'}),
			&nice_size($log->{'size'}),
			$log->{'ok'} && !$log->{'errdoms'} ? $text{'yes'} :
			 $log->{'ok'} && $log->{'errdoms'} ?
			  "<font color=#ffaa00>$text{'backuplog_part'}</font>" :
			  "<font color=#ff0000>$text{'no'}</font>"
			]);
		}
	print &ui_columns_table([ $text{'sched_dest'}, $text{'sched_doms'},
				  $text{'backuplog_who'},
				  $text{'backuplog_when'},
				  $text{'backuplog_len'},
				  $text{'backuplog_size'},
				  $text{'backuplog_ok2'} ],
				100, \@table);
				  
	}
else {
	# None found
	print "<b>",($in{'search'} ? $text{'backuplog_nomatch'} :
		     $anylogs ? $text{'backuplog_none2'} :
				$text{'backuplog_none'}),"</b><p>\n";
	}

&ui_print_footer("", $text{'index'});

