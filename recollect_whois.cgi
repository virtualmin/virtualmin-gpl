#!/usr/local/bin/perl
# recollect_whois.cgi
# Refreshes given domains whois status

require './virtual-server-lib.pl';
&ReadParse();
my $domsstr = $in{'doms'};
if ($domsstr) {
	my @doms = split(" ", $domsstr);
	foreach my $dom (@doms) {
		$d = &get_domain_by('dom', $dom);
		next if (!$d);
		next if (!&can_edit_domain($d));
		if ($in{'ignore'}) {
			# Ignore expiry forever
			$d->{'whois_ignore'} = 1;
			}
		else {
			# Re-check expiry time
			my $now = time();
			my ($exp, $err) = &get_whois_expiry($d);
			$d->{'whois_next'} = $now + 7*24*60*60 + int(rand(24*60*60));
			$d->{'whois_last'} = $now;
			$d->{'whois_err'} = $err;
			$d->{'whois_expiry'} = $exp;
			delete($d->{'whois_ignore'});
			}
		&save_domain($d);
		}
	}
&redirect(&get_referer_relative());

