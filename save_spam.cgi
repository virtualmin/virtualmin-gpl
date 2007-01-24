#!/usr/local/bin/perl
# Save spam and virus delivery options for a virtual server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'spam_err'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_spam($d) || &error($text{'spam_ecannot'});
&set_all_null_print();

# Work out what we can edit
if ($d->{'spam'}) {
	($smode, $sdest) = &get_domain_spam_delivery($d);
	if ($smode >= 0) {
		push(@what, [ 'spam', \&save_domain_spam_delivery ]);
		}
	}
if ($d->{'virus'}) {
	($vmode, $vdest) = &get_domain_virus_delivery($d);
	if ($vmode >= 0) {
		push(@what, [ 'virus', \&save_domain_virus_delivery ]);
		}
	}

# Validate spam and possibly virus inputs
foreach $w (@what) {
	($pfx, $func) = @$w;
	$mode = $in{$pfx."_mode"};
	$dest = undef;
	if ($mode == 1) {
		$dest = $in{$pfx."_file"};
		$dest =~ /\S/ && $dest !~ /\.\./ && $dest !~ /^\// ||
			&error($text{'spam_efile'});
		}
	elsif ($mode == 2) {
		$dest = $in{$pfx."_email"};
		$dest =~ /\@/ || &error($text{'spam_eemail'});
		}
	elsif ($mode == 3) {
		$dest = $in{$pfx."_dest"};
		$dest =~ /\S/ || &error($text{'spam_edest'});
		}
	&$func($d, $mode, $dest);
	}

if ($d->{'spam'}) {
	$d->{'spam_white'} = $in{'spam_white'};
	&update_spam_whitelist($d);
	&save_domain($d);
	}

if ($d->{'spam'} && &can_spam_client()) {
	&save_domain_spam_client($d, $in{'spam_client'});
	&modify_webmin($d, $d);
	}

&run_post_actions();

# All done
&webmin_log("spam", "domain", $d->{'dom'});
&domain_redirect($d);

