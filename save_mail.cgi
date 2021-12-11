#!/usr/local/bin/perl
# Save email-related options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'mail_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_mail() || &error($text{'edit_ecannot'});
$oldd = { %$d };
&require_mail();

# Validate inputs
if ($supports_bcc) {
	$in{'bcc_def'} || $in{'bcc'} =~ /^\S+\@\S+$/ ||
		&error($text{'mail_ebcc'});
	}

&ui_print_unbuffered_header(&domain_in($d), $text{'mail_title'}, "");

# Update BCC setting
if ($supports_bcc) {
	$bcc = &get_domain_sender_bcc($d);
	if (!$in{'bcc_def'}) {
		# Update BCC setting
		&$first_print(&text('mail_bccing', $in{'bcc'}));
		&save_domain_sender_bcc($d, $in{'bcc'});
		&$second_print($text{'setup_done'});
		$changed++;
		}
	elsif ($bcc && $in{'bcc_def'}) {
		# Turn off BCC
		&$first_print($text{'mail_nobcc'});
		&save_domain_sender_bcc($d, undef);
		&$second_print($text{'setup_done'});
		$changed++;
		}
	}
if ($supports_bcc == 2) {
	$rbcc = &get_domain_recipient_bcc($d);
	if (!$in{'rbcc_def'}) {
		# Update BCC setting
		&$first_print(&text('mail_rbccing', $in{'rbcc'}));
		&save_domain_recipient_bcc($d, $in{'rbcc'});
		&$second_print($text{'setup_done'});
		$changed++;
		}
	elsif ($rbcc && $in{'rbcc_def'}) {
		# Turn off BCC
		&$first_print($text{'mail_norbcc'});
		&save_domain_recipient_bcc($d, undef);
		&$second_print($text{'setup_done'});
		$changed++;
		}
	}

# Update alias mode
if (defined($in{'aliascopy'}) && $d->{'mail'}) {
	$aliasdom = &get_domain($d->{'alias'});
	if ($d->{'aliascopy'} && !$in{'aliascopy'}) {
		# Switch to catchall
		&$first_print($text{'save_aliascopy0'});
		&delete_alias_virtuals($d);
		&create_virtuser({ 'from' => '@'.$d->{'dom'},
				   'to' => [ '%1@'.$aliasdom->{'dom'} ] });
		&$second_print($text{'setup_done'});
		$changed++;
		}
	elsif (!$d->{'aliascopy'} && $in{'aliascopy'}) {
		# Switch to copy mode
		&$first_print($text{'save_aliascopy1'});
		&copy_alias_virtuals($d, $aliasdom);
		&$second_print($text{'setup_done'});
		$changed++;
		}
	$d->{'aliascopy'} = $in{'aliascopy'};
	}

# Update outgoing IP mode
if (defined($in{'dependent'}) && $supports_dependent) {
	$old_dependent = &get_domain_dependent($d) ? 1 : 0;
	if ($old_dependent != $in{'dependent'}) {
		&$first_print($in{'dependent'} ?
				&text('mail_dependenting1', $d->{'ip'}) :
				&text('mail_dependenting0'));
		&save_domain_dependent($d, $in{'dependent'});
		&$second_print($text{'setup_done'});
		$changed++;
		}
	}

# Update cloud mail provider
$oldprov = &get_domain_cloud_mail_provider($d);
if ($in{'cloud'}) {
	@provs = &list_cloud_mail_providers($d, $in{'cloudid'});
	($prov) = grep { $_->{'name'} eq $in{'cloud'} } @provs;
	$prov || &error($text{'mail_ecloud'});
	if ($prov->{'id'} && !$in{'cloudid'}) {
		&error($text{'mail_ecloudid'});
		}
	if (!$oldprov ||
	    $prov->{'name'} ne $oldprov->{'name'} ||
	    $in{'cloudid'} ne $d->{'cloud_mail_id'}) {
		&$first_print(&text('mail_cloudon', $prov->{'name'}));
		&save_domain_cloud_mail_provider($d, $prov, $in{'cloudid'});
		&$second_print($text{'setup_done'});
		$changed++;
		}
	}
else {
	if ($oldprov) {
		&$first_print(&text('mail_cloudoff'));
		&save_domain_cloud_mail_provider($d, undef);
		&$second_print($text{'setup_done'});
		$changed++;
		}
	}

# Update cloud SMTP provider
$oldsmtp = $d->{'smtp_cloud'};
$cloudsmtp = $in{'smtp_cloud'};
if (defined($cloudsmtp) && $oldsmtp ne $cloudsmtp) {
	my $oldfailed = 0;
	my @clouds = &list_smtp_clouds();
	if ($oldsmtp) {
		# Turn off the old provider
		my ($c) = grep { $_->{'name'} eq $oldsmtp } @clouds;
		&$first_print(&text('mail_smtp_cloudoff', $c->{'desc'}));
		my $sfunc = "smtpcloud_".$oldsmtp."_delete_domain";
		my $info = { 'domain' => $d->{'dom'},
			     'id' => $d->{'smtp_cloud_id'},
			     'location' => $d->{'smtp_cloud_location'}};
		my ($ok, $err) = &$sfunc($d, $info);
		if ($err) {
			&$second_print(&text('mail_smtp_cloudfailed', $err));
			$oldfailed = 1;
			}
		else {
			delete($d->{'smtp_cloud'});
			delete($d->{'smtp_cloud_id'});
			&update_smtpcloud_spf($d, $oldsmtp);
			&$second_print($text{'setup_done'});
			}
		$changed++;
		}
	if ($cloudsmtp && !$oldfailed) {
		# Setup the new provider
		my ($c) = grep { $_->{'name'} eq $cloudsmtp } @clouds;
		&$first_print(&text('mail_smtp_cloudon', $c->{'desc'}));
		my $sfunc = "smtpcloud_".$cloudsmtp."_create_domain";
		my $info = { 'domain' => $d->{'dom'} };
		my ($ok, $id, $location) = &$sfunc($d, $info);
		if ($ok) { 
			$d->{'smtp_cloud'} = $cloudsmtp;
			$d->{'smtp_cloud_id'} = $id;
			$d->{'smtp_cloud_location'} = $location;
			&update_smtpcloud_spf($d, undef);
			&$second_print($text{'setup_done'});
			}
		else {
			&$second_print(&text('mail_smtp_cloudfailed', $id));
			}
		$changed++;
		}
	}

if (!$changed) {
	&$first_print($text{'mail_nothing'});
	}

&save_domain($d);
&run_post_actions();

# All done
&webmin_log("mail", "domain", $d->{'dom'});
&ui_print_footer(&domain_footer_link($d),
		 "", $text{'index_return'});

