#!/usr/local/bin/perl
# Do a scheduled virtual server backup

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';
$host = &get_system_hostname();
if (&foreign_check("mailboxes")) {
	&foreign_require("mailboxes");
	$has_mailboxes++;
	}

# Get the schedule being used
$id = 1;
$backup_debug = 0;
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--id") {
		$id = shift(@ARGV);
		$id || &usage("Missing backup schedule ID");
		}
	elsif ($a eq "--debug") {
		$backup_debug = 1;
		}
	elsif ($a eq "--force-email") {
		$force_email = 1;
		}
	else {
		&usage("Unknown parameter $a");
		}
	}
($sched) = grep { $_->{'id'} == $id } &list_scheduled_backups();
$sched || &usage("No scheduled backup with ID $id exists");
&start_running_backup($sched);

# Work out what will be backed up
if ($sched->{'all'} == 1) {
	# All domains
	@doms = &list_domains();
	}
elsif ($sched->{'all'} == 2) {
	# All except some domains
	%exc = map { $_, 1 } split(/\s+/, $sched->{'doms'});
	@doms = grep { !$exc{$_->{'id'}} } &list_domains();
	if ($sched->{'parent'}) {
		@doms = grep { !$_->{'parent'} || !$ext{$_->{'parent'}} } @doms;
		}
	}
else {
	# Selected domains
	foreach $d (split(/\s+/, $sched->{'doms'})) {
		local $dinfo = &get_domain($d);
		if ($dinfo) {
			push(@doms, $dinfo);
			if (!$dinfo->{'parent'} && $sched->{'parent'}) {
				push(@doms, &get_domain_by("parent", $d));
				}
			}
		}
	@doms = grep { !$donedom{$_->{'id'}}++ } @doms;
	}

# Limit to those on some plan, if given
if ($sched->{'plan'}) {
	%plandoms = map { $_->{'id'}, 1 }
	  grep { &indexof($_->{'plan'}, split(/\s+/, $sched->{'plan'})) >= 0 }
	    @doms;
	@doms = grep { $plandoms{$_->{'id'}} ||
		       $plandoms{$_->{'parent'}} } @doms;
	}

# Work out who the schedule is being run for
if ($sched->{'owner'}) {
	$asd = &get_domain($sched->{'owner'});
	$owner = $asd ? $asd->{'user'} : $sched->{'owner'};
	local %access = &get_module_acl($owner);
	$cbmode = &can_backup_domain();		# Uses %access override
	@doms = grep { &can_backup_domain($_) } @doms;
	}
else {
	# Master admin
	$cbmode = 1;
	}

# Get the backup key
if ($sched->{'key'} && defined(&get_backup_key)) {
	$key = &get_backup_key($sched->{'key'});
	}

# Work out features and options
if ($sched->{'feature_all'}) {
	@do_features = ( &get_available_backup_features(),
			 &list_backup_plugins() );
	}
else {
	@do_features = split(/\s+/, $sched->{'features'});
	}
foreach $f (@do_features) {
	$options{$f} = { map { split(/=/, $_) }
			  split(/,/, $sched->{'backup_opts_'.$f}) };
	}
$options{'dir'}->{'exclude'} = $sched->{'exclude'};
@vbs = split(/\s+/, $sched->{'virtualmin'});

# Start capturing output
$first_print = \&first_save_print;
$second_print = \&second_save_print;
$indent_print = \&indent_save_print;
$outdent_print = \&outdent_save_print;

# Run any before command
$start_time = time();
if ($sched->{'before'}) {
	&$first_print("Running pre-backup command ..");
	$out .= &backquote_command("($sched->{'before'}) 2>&1 </dev/null");
	print $out;
	$output .= $out;
	if ($?) {
		&$second_print(".. failed!");
		$ok = 0;
		$size = 0;
		goto PREFAILED;
		}
	else {
		&$second_print(".. done");
		}
	}

# Execute the backup
@dests = &get_scheduled_backup_dests($sched);
@strfdests = $sched->{'strftime'} ? map { &backup_strftime($_) } @dests
				  : @dests;
$current_id = undef;
eval {
	local $main::error_must_die = 1;
	($ok, $size, $errdoms) = &backup_domains(
					\@strfdests,
					\@doms,
					\@do_features,
					$sched->{'fmt'},
					$sched->{'errors'},
					\%options,
					$sched->{'fmt'} == 2,
					\@vbs,
					$sched->{'mkdir'},
					$sched->{'onebyone'},
					$cbmode == 2,
					\&backup_cbfunc,
					$sched->{'increment'},
					1,
					$key,
					$sched->{'kill'});
	};
if ($@) {
	# Perl error during backup!
	$ok = 0;
	$output .= $@;
	}

# If purging old backups, do that now
@purges = &get_scheduled_backup_purges($sched);
if ($ok || $sched->{'errors'} == 1) {
	$i = 0;
	$asd = $cbmode == 2 ? &get_backup_as_domain(\@doms) : undef;
	foreach $dest (@dests) {
		if ($purges[$i]) {
			$current_id = undef;
			$pok = &purge_domain_backups(
				$dest, $purges[$i], $start_time, $asd);
			$ok = 0 if (!$pok);
			}
		$i++;
		}
	}

# Run any after command
if ($sched->{'after'}) {
	&$first_print("Running post-backup command ..");
	$out = &backquote_command("($sched->{'after'}) 2>&1 </dev/null");
	print $out;
	$output .= $out;
	if ($?) {
		&$second_print(".. failed!");
		}
	else {
		&$second_print(".. done");
		}
	}
&cleanup_backup_limits(0, 1);
foreach $dest (@strfdests) {
	&write_backup_log(\@doms, $dest, $sched->{'increment'}, $start_time,
			  $size, $ok, "sched", $output, $errdoms,
			  $asd ? $asd->{'user'} : undef, $key, $sched->{'id'});
	}

PREFAILED:

# Send an email to the recipient, if there are any
if ($sched->{'email'} && $has_mailboxes &&
    (!$ok || @$errdoms || !$sched->{'email_err'} || $force_email)) {
	# Construct header for backup email
	$output_header = "";
	# Nice format $dest for email
	$dest = &nice_backup_url($strfdests[0]);
	if ($ok && !@$errdoms) {
		$output_header .= &text('backup_done',
					&nice_size($size))." ";
		$subject = &text('backup_donesubject', $host, $dest);
		}
	elsif ($ok && @$errdoms) {
		$output_header .= &text('backup_partial',
					&nice_size($size))." ";
		$subject = &text('backup_partialsubject', $host, $dest);
		}
	else {
		$output_header .= $text{'backup_failed'}." ";
		$subject = &text('backup_failedsubject', $host, $dest);
		}
	$total_time = time() - $start_time;
	$output_header .= &text('backup_time',
				&nice_hour_mins_secs($total_time))."\n";
	$output_header .= "\n";

	# Add list of domains that failed
	if (@$errdoms) {
		$output_header .= $text{'backup_partial2'}."\n";
		foreach $d (@$errdoms) {
			$output_header .= "    ".$d->{'dom'}."\n";
			}
		}

	$output_header .= &text('backup_fromvirt',
				&get_virtualmin_url())."\n";
	$output_header .= "\n";
	$output = $output_header.$output;

	$mail = { 'headers' => [ [ 'From', &get_global_from_address() ],
				 [ 'Subject', &html_tags_to_text($subject) ],
				 [ 'To', $sched->{'email'} ] ],
		  'attach'  => [ { 'headers' => [ [ 'Content-type',
						    'text/plain' ] ],
				   'data' => &entities_to_ascii($output) } ]
		};
	&mailboxes::send_mail($mail);
	}

# Send email to domain owners too, if selected
%errdoms = map { $_->{'id'}, $_ } @$errdoms;
if ($sched->{'email_doms'} && $has_mailboxes &&
    (!$ok || !$sched->{'email_err'} || $force_email)) {
	@emails = &unique(map { $_->{'emailto'} } @doms);
	foreach $email (@emails) {
		# Find the domains for this email address, and their output
		@edoms = grep { $_->{'emailto'} eq $email } @doms;
		$eoutput = join("", map { $domain_output{$_->{'id'}} } @edoms);
		$eoutput .= "\n";
		$eoutput .= &text('backup_fromvirt',
				&get_virtualmin_url($edoms[0]))."\n";

		# Check if any of the domains failed
		@failededoms = grep { $errdoms{$_->{'id'}} } @edoms;
		$dest = &nice_backup_url($strfdests[0]);
		if (@failededoms) {
			$subject = &text('backup_failedsubject', $host, $dest);
			}
		else {
			$subject = &text('backup_donesubject', $host, $dest);
			}

		$mail = {
		  'headers' =>
			[ [ 'From', &get_global_from_address($edoms[0]) ],
			  [ 'Subject', &html_tags_to_text($subject) ],
			  [ 'To', $email ] ],
		  'attach'  =>
			[ { 'headers' => [ [ 'Content-type', 'text/plain' ] ],
			    'data' => &entities_to_ascii($eoutput) } ]
			};
		if ($eoutput) {
			&mailboxes::send_mail($mail);
			}
		}
	}

# Backup is done
&stop_running_backup($sched);

# Override print functions to capture output
sub first_save_print
{
local @msg = map { &html_tags_to_text(&entities_to_ascii($_)) } @_;
$output .= $indent_text.join("", @msg)."\n";
$domain_output{$current_id} .= $indent_text.join("", @msg)."\n"
	if ($current_id);
print $indent_text.join("", @msg)."\n" if ($backup_debug);
}
sub second_save_print
{
local @msg = map { &html_tags_to_text(&entities_to_ascii($_)) } @_;
$output .= $indent_text.join("", @msg)."\n\n";
$domain_output{$current_id} .= $indent_text.join("", @msg)."\n\n"
	if ($current_id);
print $indent_text.join("", @msg)."\n" if ($backup_debug);
}
sub indent_save_print
{
$indent_text .= "    ";
}
sub outdent_save_print
{
$indent_text = substr($indent_text, 4);
}

# Called during the backup process for each domain
sub backup_cbfunc
{
local ($d, $step, $info) = @_;
if ($step == 0) {
	$current_id = $d->{'id'};
	}
elsif ($step == 2) {
	$current_id = undef;
	}
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Runs one scheduled Virtualmin backup. Usually called automatically from Cron.\n";
print "\n";
print "usage: backup.pl [--id number]\n";
print "                 [--debug]\n";
print "                 [--force-email]\n";
exit(1);
}


