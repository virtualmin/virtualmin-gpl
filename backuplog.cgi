#!/usr/local/bin/perl
# Show logs of backups this user has permissions on

require './virtual-server-lib.pl';
&ReadParse();
&can_backup_log() || &error($text{'backuplg_ecannot'});
&ui_print_header(undef, $text{'backuplog_title'}, "", 'backup_logs');

# Get backups to list
$days = $in{'sched'} ? 365 : ($config{'backuplog_days'} || 7);
@logs = &list_backup_logs($in{'search'} ? undef : time()-24*60*60*$days);

$anylogs = scalar(@logs);
@logs = grep { &can_backup_log($_) } @logs;

if (!@logs) {
	# None found
	print $in{'search'} ? $text{'backuplog_nomatch'} :
		   $anylogs ? $text{'backuplog_none2'} :
			      $text{'backuplog_none'},"\n";
	return;
	}

# Show search form
if ($in{'search'}) {
	my $search = $in{'search'} // '';
	my %by = (
		schedule  => sub { ($_[0]{'sched'}        // '') =~ /$_[1]/i },
		user      => sub { ($_[0]{'user'}         // '') =~ /$_[1]/i },
		domain    => sub { ($_[0]{'doms'}         // '') =~ /$_[1]/i },
		dest      => sub { ($_[0]{'dest'}         // '') =~ /$_[1]/i },
		desc      => sub { ($_[0]{'desc'}         // '') =~ /$_[1]/i },
		time => sub { (&make_date($_[0]{'start'}) // '') =~ /$_[1]/i },
		type => sub {
			my $label = $_[0]{increment}
				? $text{"viewbackup_inc1"}
				: $text{"viewbackup_inc0"};
			return $label =~ /$_[1]/i;
		},
		size => sub {
			my ($log) = @_;
			my $sz = $log->{size} // 0;
			my @conds;
			# Parse one or few comparisons: >10M or <1G >512K
			while ($_[1] =~ /([<>]=?)\s*([0-9]+(?:\.[0-9]+)?)\s*([kmg])?b?/ig) {
				my ($op, $num, $u) = ($1, $2+0, lc($3 // ''));
				my $mult = $u eq 'k' ? 1024
					: $u eq 'm' ? 1024*1024
					: $u eq 'g' ? 1024*1024*1024
					: 1;
				push @conds, [$op, $num * $mult];
				}
			
			return 1 unless (@conds);
			
			foreach my $c (@conds) {
				my ($op, $bytes) = @$c;
				return 0 if ($op eq '>'  && !($sz >  $bytes));
				return 0 if ($op eq '>=' && !($sz >= $bytes));
				return 0 if ($op eq '<'  && !($sz <  $bytes));
				return 0 if ($op eq '<=' && !($sz <= $bytes));
				}
			return 1;
			},
		status => sub {
			my $ok   = $_[0]{'ok'} // 0;
			my $errs = $_[0]{'errdoms'};
			my $key  = $ok ? ($errs ? 'partial' : 'ok') : 'failed';
			my $txt  = $ok
				? ($errs
					? $text{'backuplog_status_partial'}
					: $text{'backuplog_status_ok'})
				: $text{'backuplog_status_failed'};
			lc($_[1]) eq $key || $txt =~ /\Q$_[1]\E/i;
			},
		plugin => sub { ($_[0]{'plugged'}  // '') =~ /$_[1]/i },
	);

	if ($search =~ /[a-z_]+\s*[:=]/i) {
		# Support multi field terms search separated by commas
		my @terms = grep length, map { s/^\s+|\s+$//gr }
					 split /,/, $search;

		# Build anded filters
		my @filters;
		foreach my $t (@terms) {
			next unless $t =~ /\A([a-z_]+)\s*[:=]\s*(.+)\z/i;
			my ($k, $v) = (lc $1, $2);
			push @filters, sub {
				my ($log) = @_;
				$by{$k} ? $by{$k}->($log, $v) : 0
				};
			}
		if (@filters) {
			@logs = grep {
					my $log = $_;
					my $ok = 1;
					for my $f (@filters) {
						$ok &&= $f->($log);
						last unless ($ok);
						}
					$ok;
				} @logs;
			}
		}
	else {
		@logs = grep { $_->{'user'} eq $in{'search'} ||
			       $_->{'doms'} =~ /\Q$in{'search'}\E/i ||
			       $_->{'dest'} =~ /\Q$in{'search'}\E/i } @logs;

		}
	}
elsif ($in{'sched'}) {
	($sched) = grep { $_->{'id'} eq $in{'sched'} }
			&list_scheduled_backups();
	unless ($sched) {
		print &ui_alert_box($text{'backuplg_esched'}, 'danger',
			undef, undef, '');
		return;
		}
	@logs = grep { $_->{'sched'} eq $in{'sched'} } @logs;
	}
else {
	$placeholder = &text('backuplog_days', $days);
	}

# Tell the user what he is searching for
if ($in{'search'}) {
	my $msg;
	if (!@logs) {
		$msg =  &text('backuplog_nomatch',
			      "<tt>".&html_escape($in{'search'})."</tt>");
		print &ui_alert_box($msg, 'warn', undef, undef, '');
		}
	else {
		$placeholder = &text('backuplog_match',
			     &html_escape($in{'search'}));
		}
	}
elsif ($in{'sched'}) {
	my $msg;
	if ($sched->{desc}) {
		$msg = &text('backuplog_scheddesc', $sched->{'desc'});
		}
	else {
		@dests = &get_scheduled_backup_dests($sched);
		@nices = map { &nice_backup_url($_, 1) } @dests;
		$msg = &text('backuplog_sched', "<tt>$nices[0]</tt>");
		}
		
	print &ui_alert_box($msg, 'info', undef, undef, '');
	}

print &ui_form_start("backuplog.cgi");
print "$text{'backuplog_search'}&nbsp;\n";
print &ui_textbox("search", $in{'search'}, 35, undef, undef, "placeholder='$placeholder'");
print &ui_hidden("return", $in{'return'}) if ($in{'return'});
print &ui_submit($text{'ui_searchok'});
print &ui_form_end(),"<p>\n";

if (@logs) {
	# Show in a table
	@table = ( );
	$hasdesc = 0;
	foreach $log (@logs) {
		$hasdesc++ if ($log->{'desc'});
		}
	foreach $log (sort { $b->{'start'} <=> $a->{'start'} } @logs) {
		@dnames = &backup_log_own_domains($log);
		next if (!@dnames);
		$ddesc = scalar(@dnames) == 0 ?
				$text{'backuplog_nodoms'} :
			 scalar(@dnames) <= 2 ?
				join(", ", @dnames) :
				&text('backuplog_doms', scalar(@dnames));
		my $link = &make_link('view_backuplog.cgi',
				      ['id', $log->{'id'}], 'search', 'plugin',
				      'return');
		push(@table, [
			"<a href='$link'>".
			 &nice_backup_url($log->{'dest'}, 1, 1)."</a>",
			$ddesc,
			$hasdesc ? ( &html_escape($log->{'desc'}) ) : ( ),
		        $log->{'user'} || "<i>root</i>",
			&make_date($log->{'start'}),
			&short_nice_hour_mins_secs(
				$log->{'end'} - $log->{'start'}),
			$log->{'increment'} == 1 ? $text{'viewbackup_inc1'} :
						   $text{'viewbackup_inc0'},
			&nice_size($log->{'size'}),
			$log->{'ok'} && !$log->{'errdoms'} ? $text{'backuplog_status_ok'} :
			 $log->{'ok'} && $log->{'errdoms'} ?
			  &ui_text_color($text{'backuplog_status_partial'}, 'warn') :
			  &ui_text_color($text{'backuplog_status_failed'}, 'danger')
			]);
		}
	print &ui_columns_table([ $text{'sched_dest'}, $text{'sched_doms'},
				  $hasdesc ? ( $text{'backuplog_desc'} ) : ( ),
				  $text{'backuplog_who'},
				  $text{'backuplog_when'},
				  $text{'backuplog_len'},
				  $text{'backuplog_incr'},
				  $text{'backuplog_size'},
				  $text{'backuplog_status'} ],
				100, \@table);
				  
	}
