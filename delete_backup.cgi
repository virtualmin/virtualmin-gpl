#!/usr/local/bin/perl
# Delete one backup, after asking for confirmation

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'dbackup_err'});

# Get the log and check permissions
$in{'id'} =~ /^[0-9\.\-]+$/ || &error($text{'viewbackup_eid'});
$log = &get_backup_log($in{'id'});
$log || &error($text{'viewbackup_egone'});
&can_backup_log($log) || &error($text{'viewbackup_ecannot'});
@alldnames = split(/\s+/, $log->{'doms'});
@owndnames = &backup_log_own_domains($log);
scalar(@alldnames) == scalar(@owndnames) ||
	&error($text{'dbackup_edoms'});

&ui_print_header(undef, $text{'dbackup_title'}, "");

if ($in{'confirm'}) {
	# Do it
	&$first_print(&text('dbackup_doing', &nice_backup_url($log->{'dest'})));
	$err = &delete_backup_from_log($log);
	if (!$err) {
		$err = &delete_backup_log($log);
		}
	if ($err) {
		&$second_print(&text('dbackup_failed', $err));
		}
	else {
		&$second_print(&text('dbackup_done'));
		}
	}
else {
	# Ask first
	print &ui_confirmation_form(
		"delete_backup.cgi",
		&text('dbackup_rusure', &nice_size($log->{'size'}),
					scalar(@alldnames),
					&nice_backup_url($log->{'dest'})),
		[ [ "id", $in{'id'} ] ],
		[ [ "confirm", $text{'dbackup_confirm'} ] ],
		);
	}

&ui_print_footer("backuplog.cgi", $text{'backuplog_return'});
