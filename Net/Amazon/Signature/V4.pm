package Net::Amazon::Signature::V4;

use strict;
use warnings;
use sort 'stable';

use Digest::SHA qw/sha256_hex hmac_sha256 hmac_sha256_hex/;
use Time::Piece ();
use URI::Escape;

our $ALGORITHM = 'AWS4-HMAC-SHA256';

=head1 NAME

Net::Amazon::Signature::V4 - Implements the Amazon Web Services signature version 4, AWS4-HMAC-SHA256

=head1 VERSION

Version 0.21

=cut

our $VERSION = '0.21';


=head1 SYNOPSIS

    use Net::Amazon::Signature::V4;

    my $sig = Net::Amazon::Signature::V4->new( $access_key_id, $secret, $endpoint, $service );
    my $req = HTTP::Request->parse( $request_string );
    my $signed_req = $sig->sign( $req );
    ...

=head1 DESCRIPTION

This module signs an HTTP::Request to Amazon Web Services by appending an Authorization header. Amazon Web Services signature version 4, AWS4-HMAC-SHA256, is used.

The primary purpose of this module is to be used by Net::Amazon::Glacier.

=head1 METHODS

=head2 new

    my $sig = Net::Amazon::Signature::V4->new( $access_key_id, $secret, $endpoint, $service );
    my $sig = Net::Amazon::Signature::V4->new({
        access_key_id => $access_key_id,
        secret        => $secret,
        endpoint      => $endpoint,
        service       => $service,
    });

Constructs the signature object, which is used to sign requests.

Note that the access key ID is an alphanumeric string, not your account ID. The endpoint could be "eu-west-1", and the service could be "glacier".

Since version 0.20, parameters can be passed in a hashref. The keys C<access_key_id>, C<secret>, C<endpoint>, and C<service> are required.
C<security_token>, if passed, will be applied to each signed request as the C<X-Amz-Security-Token> header.

=cut

sub new {
	my $class = shift;
	my $self = {};
	if (@_ == 1 and ref $_[0] eq 'HASH') {
		@$self{keys %{$_[0]}} = values %{$_[0]};
	} else {
		@$self{qw(access_key_id secret endpoint service)} = @_;
	}
	# The URI should not be double escaped for the S3 service
	$self->{no_escape_uri} = ( lc($self->{service}) eq 's3' ) ? 1 : 0;
	bless $self, $class;
	return $self;
}

=head2 sign

    my $signed_request = $sig->sign( $request );

Signs a request with your credentials by appending the Authorization header. $request should be an HTTP::Request. The signed request is returned.

=cut

sub sign {
	my ( $self, $request ) = @_;
	my $authz = $self->_authorization( $request );
	$request->header( Authorization => $authz );
	return $request;
}

# _headers_to_sign:
# Return the sorted lower case headers as required by the generation of canonical headers

sub _headers_to_sign {
	my $req = shift;

	return sort { $a cmp $b } map { lc } $req->headers->header_field_names;
}

# _canonical_request:
# Construct the canonical request string from an HTTP::Request.

sub _canonical_request {
	my ( $self, $req ) = @_;

	my $creq_method = $req->method;

	my ( $creq_canonical_uri, $creq_canonical_query_string ) = 
		( $req->uri =~ m@([^?]*)\?(.*)$@ )
		? ( $1, $2 )
		: ( $req->uri, '' );
	$creq_canonical_uri =~ s@^https?://[^/]*/?@/@;
	$creq_canonical_uri = $self->_simplify_uri( $creq_canonical_uri );
	$creq_canonical_query_string = _sort_query_string( $creq_canonical_query_string );

	# Ensure Host header is present as its required
	if (!$req->header('host')) {
		my $host = $req->uri->_port ? $req->uri->host_port : $req->uri->host;
		$req->header('Host' => $host);
	}
	my $creq_payload_hash = $req->header('x-amz-content-sha256');
	if (!$creq_payload_hash) {
		$creq_payload_hash = sha256_hex($req->content);
		# X-Amz-Content-Sha256 must be specified now
		$req->header('X-Amz-Content-Sha256' => $creq_payload_hash);
	}

	# There's a bug in AMS4 which causes requests without x-amz-date set to be rejected
	# so we always add one if its not present.
	my $amz_date = $req->header('x-amz-date');
	if (!$amz_date) {
		$req->header('X-Amz-Date' => _req_timepiece($req)->strftime('%Y%m%dT%H%M%SZ'));
	}
	if (defined $self->{security_token} and !defined $req->header('X-Amz-Security-Token')) {
		$req->header('X-Amz-Security-Token' => $self->{security_token});
	}
	my @sorted_headers = _headers_to_sign( $req );
	my $creq_canonical_headers = join '',
		map {
			sprintf "%s:%s\x0a",
				lc,
				join ',', sort {$a cmp $b } _trim_whitespace($req->header($_) )
		}
		@sorted_headers;
	my $creq_signed_headers = join ';', map {lc} @sorted_headers;
	my $creq = join "\x0a",
		$creq_method, $creq_canonical_uri, $creq_canonical_query_string,
		$creq_canonical_headers, $creq_signed_headers, $creq_payload_hash;
	return $creq;
}

# _string_to_sign
# Construct the string to sign.

sub _string_to_sign {
	my ( $self, $req ) = @_;
	my $dt = _req_timepiece( $req );
	my $creq = $self->_canonical_request($req);
	my $sts_request_date = $dt->strftime( '%Y%m%dT%H%M%SZ' );
	my $sts_credential_scope = join '/', $dt->strftime('%Y%m%d'), $self->{endpoint}, $self->{service}, 'aws4_request';
	my $sts_creq_hash = sha256_hex( $creq );

	my $sts = join "\x0a", $ALGORITHM, $sts_request_date, $sts_credential_scope, $sts_creq_hash;
	return $sts;
}

# _authorization
# Construct the authorization string

sub _authorization {
	my ( $self, $req ) = @_;

	my $dt = _req_timepiece( $req );
	my $sts = $self->_string_to_sign( $req );
	my $k_date    = hmac_sha256( $dt->strftime('%Y%m%d'), 'AWS4' . $self->{secret} );
	my $k_region  = hmac_sha256( $self->{endpoint},        $k_date    );
	my $k_service = hmac_sha256( $self->{service},         $k_region  );
	my $k_signing = hmac_sha256( 'aws4_request',           $k_service );

	my $authz_signature = hmac_sha256_hex( $sts, $k_signing );
	my $authz_credential = join '/', $self->{access_key_id}, $dt->strftime('%Y%m%d'), $self->{endpoint}, $self->{service}, 'aws4_request';
	my $authz_signed_headers = join ';', _headers_to_sign( $req );

	my $authz = "$ALGORITHM Credential=$authz_credential,SignedHeaders=$authz_signed_headers,Signature=$authz_signature";
	return $authz;

}

=head1 AUTHOR

Tim Nordenfur, C<< <tim at gurka.se> >>

Maintained by Dan Book, C<< <dbook at cpan.org> >>

=cut

sub _simplify_uri {
	my $self = shift;
	my $orig_uri = shift;
	my @parts = split /\//, $orig_uri;
	my @simple_parts = ();
	for my $part ( @parts ) {
		if ( $part eq '' || $part eq '.' ) {
		} elsif ( $part eq '..' ) {
			pop @simple_parts;
		} else {
			if ( $self->{no_escape_uri} ) {
				push @simple_parts, $part;
			}
			else {
				push @simple_parts, uri_escape($part);
			}
		}
	}
	my $simple_uri = '/' . join '/', @simple_parts;
	$simple_uri .= '/' if $orig_uri =~ m@/$@ && $simple_uri !~ m@/$@;
	return $simple_uri;
}
sub _sort_query_string {
	return '' unless $_[0];
	my @params;
	for my $param ( split /&/, $_[0] ) {
		my ( $key, $value ) = 
			map { tr/+/ /; uri_escape( uri_unescape( $_ ) ) } # escape all non-unreserved chars
			split /=/, $param;
		push @params, [$key, (defined $value ? $value : '')];
	}
	return join '&',
		map { join '=', @$_ }
		sort { ( $a->[0] cmp $b->[0] ) || ( $a->[1] cmp $b->[1] ) }
		@params;
}
sub _trim_whitespace {
	return map { my $str = $_; $str =~ s/^\s*//; $str =~ s/\s*$//; $str } @_;
}
sub _str_to_timepiece {
	my $date = shift;
	if ( $date =~ m/^\d{8}T\d{6}Z$/ ) {
		# assume basic ISO 8601, as demanded by AWS
		return Time::Piece->strptime($date, '%Y%m%dT%H%M%SZ');
	} else {
		# assume the format given in the AWS4 test suite
		$date =~ s/^.{5}//; # remove weekday, as Amazon's test suite contains internally inconsistent dates
		return Time::Piece->strptime($date, '%d %b %Y %H:%M:%S %Z');
	}
}
sub _req_timepiece {
	my $req = shift;
	my $x_date = $req->header('X-Amz-Date');
	my $date = $x_date || $req->header('Date');
	if (!$date) {
		# No date set by the caller so set one up
		my $piece = Time::Piece::gmtime;
		$req->date($piece->epoch);
		return $piece
	}
	return _str_to_timepiece($date);
}

=head1 BUGS

Please report any bugs or feature requests to C<bug-Net-Amazon-Signature-V4 at rt.cpan.org>, or through
the web interface at L<https://rt.cpan.org/Public/Bug/Report.html?Queue=Net-Amazon-Signature-V4>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::Amazon::Signature::V4


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<https://rt.cpan.org/Public/Dist/Display.html?Name=Net-Amazon-Signature-V4>

=item * Source on GitHub

L<https://github.com/Grinnz/Net-Amazon-Signature-V4>

=item * Search CPAN

L<https://metacpan.org/release/Net-Amazon-Signature-V4>

=back

=head1 LICENSE AND COPYRIGHT

This software is copyright (c) 2012 by Tim Nordenfur.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.


=cut

1; # End of Net::Amazon::Signature::V4
