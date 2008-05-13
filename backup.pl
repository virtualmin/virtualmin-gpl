#!/usr/local/bin/perl
# Do a scheduled virtual server backup

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';
$host = &get_system_hostname();
if (&foreign_check("mailboxes")) {
	&foreign_require("mailboxes", "mailboxes-lib.pl");
	$has_mailboxes++;
	}

# Work out what will be backed up
if ($config{'backup_all'} == 1) {
	@doms = &list_domains();
	}
elsif ($config{'backup_all'} == 2) {
	%exc = map { $_, 1 } split(/\s+/, $config{'backup_doms'});
	@doms = grep { !$exc{$_->{'id'}} } &list_domains();
	if ($in{'parent'}) {
		@doms = grep { !$_->{'parent'} || !$ext{$_->{'parent'}} } @doms;
		}
	}
else {
	foreach $d (split(/\s+/, $config{'backup_doms'})) {
		local $dinfo = &get_domain($d);
		if ($dinfo) {
			push(@doms, $dinfo);
			if (!$dinfo->{'parent'} && $in{'parent'}) {
				push(@doms, &get_domain_by("parent", $d));
				}
			}
		}
	@doms = grep { !$donedom{$_->{'id'}}++ } @doms;
	}

# Work out features and options
if ($config{'backup_feature_all'}) {
	@do_features = ( &get_available_backup_features(), @backup_plugins );
	}
else {
	@do_features = grep { $config{'backup_feature_'.$_} }
			    (@backup_features, @backup_plugins);
	}
foreach $f (@do_features) {
	$options{$f} = { map { split(/=/, $_) }
			  split(/,/, $config{'backup_opts_'.$f}) };
	}
@vbs = split(/\s+/, $config{'backup_virtualmin'});

# Do the backup, capturing any output
$first_print = \&first_save_print;
$second_print = \&second_save_print;
$indent_print = \&indent_save_print;
$outdent_print = \&outdent_save_print;
if ($config{'backup_strftime'}) {
	$dest = &backup_strftime($config{'backup_dest'});
	}
else {
	$dest = $config{'backup_dest'};
	}
$start_time = time();
$current_id = undef;
($ok, $size) = &backup_domains($dest, \@doms, \@do_features,
			       $config{'backup_fmt'},
			       $config{'backup_errors'}, \%options,
			       $config{'backup_fmt'} == 2,
			       \@vbs,
			       $config{'backup_mkdir'},
			       $config{'backup_onebyone'},
			       0,
			       \&backup_cbfunc);

# Send an email to the recipient, if there are any
if ($config{'backup_email'} && $has_mailboxes &&
    (!$ok || !$config{'backup_email_err'})) {
	if ($ok) {
		$output .= &text('backup_done', &nice_size($size))." ";
		}
	else {
		$output .= $text{'backup_failed'}." ";
		}
	$total_time = time() - $start_time;
	$output .= &text('backup_time', &nice_hour_mins_secs($total_time))."\n";
	$mail = { 'headers' => [ [ 'From', &get_global_from_address() ],
				 [ 'Subject', "Backup of Virtualmin on $host" ],
				 [ 'To', $config{'backup_email'} ] ],
		  'attach'  => [ { 'headers' => [ [ 'Content-type',
						    'text/plain' ] ],
				   'data' => &entities_to_ascii($output) } ]
		};
	&mailboxes::send_mail($mail);
	}

# Send email to domain owners too, if selected
if ($config{'backup_email_doms'} && $has_mailboxes &&
    (!$ok || !$config{'backup_email_err'})) {
	@emails = &unique(map { $_->{'emailto'} } @doms);
	foreach $email (@emails) {
		@edoms = grep { $_->{'emailto'} eq $email } @doms;
		$eoutput = join("", map { $domain_output{$_->{'id'}} } @edoms);
		$mail = {
		  'headers' =>
			[ [ 'From', &get_global_from_address($edoms[0]) ],
			  [ 'Subject', "Backup of Virtualmin on $host" ],
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

sub first_save_print {
$output .= $indent_text.join("", @_)."\n";
$domain_output{$current_id} .= $indent_text.join("", @_)."\n"
	if ($current_id);
}
sub second_save_print {
$output .= $indent_text.join("", @_)."\n\n";
$domain_output{$current_id} .= $indent_text.join("", @_)."\n\n"
	if ($current_id);
}
sub indent_save_print {
$indent_text .= "    ";
}
sub outdent_save_print {
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
