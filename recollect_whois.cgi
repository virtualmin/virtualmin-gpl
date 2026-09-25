#!/usr/local/bin/perl
# recollect_whois.cgi
# Refreshes given domains whois status

require './virtual-server-lib.pl';
&ReadParse();
my $domsstr = $in{'doms'};
if ($domsstr) {
	my @doms = split(" ", $domsstr);
	foreach my $dom (@doms) {
		my $d = &get_domain_by('dom', $dom);
		next if (!$d);
		next if (!&can_edit_domain($d));
		# Recheck access to the current record before updating WHOIS settings.
		my $locked;
		$d = &get_lock_domain($d, \$locked);
		if (!$d || !&can_edit_domain($d)) {
			&unlock_domain($d) if ($locked);
			next;
			}
		eval {
			local $main::error_must_die = 1;
			local $domain_lock_scope{$d->{'id'}} = $$;
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
			};
		my $err = $@;
		&unlock_domain($d) if ($locked);
		delete($main::get_domain_cache{$d->{'id'}}) if ($err);
		&error($err) if ($err);
		}
	}
&redirect(&get_referer_relative());

