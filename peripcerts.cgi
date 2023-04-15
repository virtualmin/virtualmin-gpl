#!/usr/local/bin/perl
# Update per-IP certs for all possible services

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'cert_eperiperr'});
$d = &get_domain($in{'dom'});
&can_edit_domain($d) && &can_edit_ssl() || &error($text{'edit_ecannot'});
&can_webmin_cert() || &error($text{'edit_ecannot'});

# Update state of all certs
@already = &get_all_domain_service_ssl_certs($d);
foreach my $st (&list_service_ssl_cert_types()) {
	next if (!$st->{'dom'} && !$st->{'virt'});
	next if (!$st->{'dom'} && !$d->{'virt'});
	($a) = grep { $_->{'d'} && $_->{'id'} eq $st->{'id'} } @already;
	$func = "sync_".$st->{'id'}."_ssl_cert";
	my $ok = 1;
	if ($in{'enable'} && !$a) {
		# Need to enable per-IP cert
		$ok = &$func($d, 1);
		}
	elsif (!$in{'enable'} && $a) {
		# Need to remove per-IP cert
		$ok = &$func($d, 0);
		}
	if ($ok < 0) {
		&error(&text('cert_eperipinst', $st->{'id'}));
		}
	elsif (defined($ok) && $ok == 0) {
		&error(&text('cert_eperipfail', $st->{'id'}));
		}
	}

&run_post_actions_silently();
&webmin_log("peripcerts", "domain", $d->{'dom'}, $d);
&redirect("cert_form.cgi?dom=$d->{'id'}");

