package IDNA::Punycode;

use strict;
our $VERSION = 0.03;

require Exporter;
our @ISA	= qw(Exporter);
our @EXPORT = qw(encode_punycode decode_punycode idn_prefix);

use integer;

our $DEBUG = 0;
our $PREFIX = 'xn--';

use constant BASE => 36;
use constant TMIN => 1;
use constant TMAX => 26;
use constant SKEW => 38;
use constant DAMP => 700;
use constant INITIAL_BIAS => 72;
use constant INITIAL_N => 128;

my $Delimiter = chr 0x2D;
my $BasicRE   = qr/[\x00-\x7f]/;

sub _croak { require Carp; Carp::croak(@_); }

sub idn_prefix {
	$PREFIX = shift;
}

sub digit_value {
	my $code = shift;
	return ord($code) - ord("A") if $code =~ /[A-Z]/;
	return ord($code) - ord("a") if $code =~ /[a-z]/;
	return ord($code) - ord("0") + 26 if $code =~ /[0-9]/;
	return;
}

sub code_point {
	my $digit = shift;
	return $digit + ord('a') if 0 <= $digit && $digit <= 25;
	return $digit + ord('0') - 26 if 26 <= $digit && $digit <= 36;
	die 'NOT COME HERE';
}

sub adapt {
	my($delta, $numpoints, $firsttime) = @_;
	$delta = $firsttime ? $delta / DAMP : $delta / 2;
	$delta += $delta / $numpoints;
	my $k = 0;
	while ($delta > ((BASE - TMIN) * TMAX) / 2) {
		$delta /= BASE - TMIN;
		$k += BASE;
	}
	return $k + (((BASE - TMIN + 1) * $delta) / ($delta + SKEW));
}

sub decode_punycode {
	my $code = shift;

	my $n	  = INITIAL_N;
	my $i	  = 0;
	my $bias   = INITIAL_BIAS;
	my @output;

	if ($PREFIX) {
		if ($code !~ /^$PREFIX/) {
			return $code;
		}
		$code =~ s/^$PREFIX//;
	}

	if ($code =~ s/(.*)$Delimiter//o) {
		push @output, map ord, split //, $1;
		return _croak('non-basic code point') unless $1 =~ /^$BasicRE*$/o;
	}

	while ($code) {
		my $oldi = $i;
		my $w	= 1;
		LOOP:
		for (my $k = BASE; 1; $k += BASE) {
			my $cp = substr($code, 0, 1, '');
			my $digit = digit_value($cp);
			defined $digit or return _croak("invalid punycode input");
			$i += $digit * $w;
			my $t = ($k <= $bias) ? TMIN
			: ($k >= $bias + TMAX) ? TMAX : $k - $bias;
			last LOOP if $digit < $t;
			$w *= (BASE - $t);
		}
		$bias = adapt($i - $oldi, @output + 1, $oldi == 0);
		warn "bias becomes $bias" if $DEBUG;
		$n += $i / (@output + 1);
		$i = $i % (@output + 1);
		splice(@output, $i, 0, $n);
		warn join " ", map sprintf('%04x', $_), @output if $DEBUG;
		$i++;
	}
	return join '', map chr, @output;
}

sub encode_punycode {
	my $input = shift;
	# my @input = split //, $input; # doesn't work in 5.6.x!
	my @input = map substr($input, $_, 1), 0..length($input)-1;

	my $n	 = INITIAL_N;
	my $delta = 0;
	my $bias  = INITIAL_BIAS;

	my @output;
	my @basic = grep /$BasicRE/, @input;
	my $h = my $b = @basic;
	#push @output, @basic, $Delimiter if $b > 0;
	push @output, @basic if $b > 0;
	warn "basic codepoints: (@output)" if $DEBUG;

	if ($h < @input) {
		$PREFIX && unshift(@output, $PREFIX);
		push(@output, $Delimiter);
	} else {
		return join '', @output;
	}

	while ($h < @input) {
		my $m = min(grep { $_ >= $n } map ord, @input);
		warn sprintf "next code point to insert is %04x", $m if $DEBUG;
		$delta += ($m - $n) * ($h + 1);
		$n = $m;
		for my $i (@input) {
			my $c = ord($i);
			$delta++ if $c < $n;
			if ($c == $n) {
				my $q = $delta;
				LOOP:
				for (my $k = BASE; 1; $k += BASE) {
					my $t = ($k <= $bias) ? TMIN :
					($k >= $bias + TMAX) ? TMAX : $k - $bias;
					last LOOP if $q < $t;
					my $cp = code_point($t + (($q - $t) % (BASE - $t)));
					push @output, chr($cp);
					$q = ($q - $t) / (BASE - $t);
				}
				push @output, chr(code_point($q));
				$bias = adapt($delta, $h + 1, $h == $b);
				warn "bias becomes $bias" if $DEBUG;
				$delta = 0;
				$h++;
			}
		}
		$delta++;
		$n++;
	}
	return join '', @output;
}

sub min {
	my $min = shift;
	for (@_) { $min = $_ if $_ <= $min }
	return $min;
}

1;
__END__

=head1 NAME

IDNA::Punycode - encodes Unicode string in Punycode

=head1 SYNOPSIS

  use IDNA::Punycode;
  idn_prefix('xn--');
  $punycode = encode_punycode($unicode);
  $unicode  = decode_punycode($punycode);

=head1 DESCRIPTION

IDNA::Punycode is a module to encode / decode Unicode strings into
Punycode, an efficient encoding of Unicode for use with IDNA.

This module requires Perl 5.6.0 or over to handle UTF8 flagged Unicode
strings.

=head1 FUNCTIONS

This module exports following functions by default.

=over 4

=item encode_punycode

  $punycode = encode_punycode($unicode);

takes Unicode string (UTF8-flagged variable) and returns Punycode
encoding for it.

=item decode_punycode

  $unicode = decode_punycode($punycode)

takes Punycode encoding and returns original Unicode string.

=item idn_prefix

  idn_prefix($prefix);

causes encode_punycode() to add $prefix to ACE-string after conversion.
As a side-effect decode_punycode() will only consider strings
beginning with $prefix as punycode representations.

According to RFC 3490 the ACE prefix "xn--" had been chosen as the
standard.  Thus, "xn--" is also the default ACE prefix.  For compatibility
I'm leaving idn_prefix() in the module.  Use C<idn_prefix(undef)> to
get the old behaviour.

=back

These functions throws exceptionsn on failure. You can catch 'em via
C<eval>.

=head1 AUTHORS

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt> is the original
author and wrote almost all the code.

Robert Urban E<lt>urban@UNIX-Beratung.deE<gt> added C<idn_prefix()>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

http://www.ietf.org/internet-drafts/draft-ietf-idn-punycode-01.txt

L<Encode::Punycode>

=cut
