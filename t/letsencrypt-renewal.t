#!/usr/bin/perl

use strict;
use warnings;
no warnings qw(once redefine);
use Test::More;
use FindBin;

do "$FindBin::Bin/../feature-ssl.pl" or die "$@ $!";

my $day = 24 * 60 * 60;
local $main::config{'acme_renewal_max_days'};

# Use the 21-day default for a 90-day certificate.
is(main::letsencrypt_renewal_before_seconds(
	1, 1 + 90 * $day), 21 * $day,
	'90-day certificate uses a 21-day renewal window');

# A 64-day certificate keeps the 21-day window, which opens after 43 days.
is(main::letsencrypt_renewal_before_seconds(
	1, 1 + 64 * $day), 21 * $day,
	'64-day certificate uses a 21-day renewal window');

# Limit a large hidden override to the final third of the certificate lifetime.
$main::config{'acme_renewal_max_days'} = 60;
is(main::letsencrypt_renewal_before_seconds(
	1, 1 + 64 * $day), 64 * $day / 3,
	'64-day certificate limits a large global renewal window');

# A 45-day certificate uses a 15-day window, which opens after 30 days.
delete($main::config{'acme_renewal_max_days'});
is(main::letsencrypt_renewal_before_seconds(
	1, 1 + 45 * $day), 15 * $day,
	'45-day certificate uses a 15-day renewal window');

# Preserve a smaller hidden override because it opens renewal later.
$main::config{'acme_renewal_max_days'} = 7;
is(main::letsencrypt_renewal_before_seconds(
	1, 1 + 45 * $day), 7 * $day,
	'smaller global renewal window is preserved');

# A six-day certificate uses the final half of its lifetime for renewal.
delete($main::config{'acme_renewal_max_days'});
is(main::letsencrypt_renewal_before_seconds(
	1, 1 + 6 * $day), 3 * $day,
	'six-day certificate uses a three-day renewal window');

# Keep the hidden override if certificate dates cannot be compared.
$main::config{'acme_renewal_max_days'} = 9;
is(main::letsencrypt_renewal_before_seconds(undef, undef), 9 * $day,
	'missing certificate dates keep the global renewal window');

# Ignore a malformed hidden override and use the default.
$main::config{'acme_renewal_max_days'} = 'invalid';
is(main::letsencrypt_renewal_before_seconds(1, 1 + 90 * $day), 21 * $day,
	'invalid global renewal window uses the default');

# Treat zero as unset and use the default.
$main::config{'acme_renewal_max_days'} = 0;
is(main::letsencrypt_renewal_before_seconds(1, 1 + 90 * $day), 21 * $day,
	'zero global renewal window uses the default');

# Treat a zero value with leading zeroes as unset too.
$main::config{'acme_renewal_max_days'} = '000';
is(main::letsencrypt_renewal_before_seconds(1, 1 + 90 * $day), 21 * $day,
	'zero-padded global renewal window uses the default');

done_testing();
