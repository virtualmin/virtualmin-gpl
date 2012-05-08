#!/usr/bin/perl

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

package S3;

use base qw(Exporter);

@EXPORT_OK = qw(canonical_string encode merge_meta $DEFAULT_HOST $PORTS_BY_SECURITY $AMAZON_HEADER_PREFIX $METADATA_PREFIX urlencode);

use strict;
use warnings;

use Digest::HMAC_SHA1;
use MIME::Base64 qw(encode_base64);
use URI::Escape;
use LWP::UserAgent;
use HTTP::Request;


our $DEFAULT_HOST = 's3.amazonaws.com';
our $PORTS_BY_SECURITY = { 0 => 80, 1 => 443 };
our $AMAZON_HEADER_PREFIX = 'x-amz-';
our $METADATA_PREFIX = 'x-amz-meta-';

sub trim {
    my ($value) = @_;

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;
    return $value;
}

# generate a canonical string for the given parameters.  expires is optional and is
# only used by query string authentication.
sub canonical_string {
    my ($method, $path, $headers, $expires) = @_;
    my %interesting_headers = ();
    while (my ($key, $value) = each %$headers) {
        my $lk = lc $key;
        if (
            $lk eq 'content-md5' or
            $lk eq 'content-type' or
            $lk eq 'date' or
            $lk =~ /^$AMAZON_HEADER_PREFIX/
        ) {
            $interesting_headers{$lk} = trim($value);
        }
    }

    # these keys get empty strings if they don't exist
    $interesting_headers{'content-type'} ||= '';
    $interesting_headers{'content-md5'} ||= '';

    # just in case someone used this.  it's not necessary in this lib.
    $interesting_headers{'date'} = '' if $interesting_headers{'x-amz-date'};

    # if you're using expires for query string auth, then it trumps date
    # (and x-amz-date)
    $interesting_headers{'date'} = $expires if $expires;

    my $buf = "$method\n";
    foreach my $key (sort keys %interesting_headers) {
        if ($key =~ /^$AMAZON_HEADER_PREFIX/) {
            $buf .= "$key:$interesting_headers{$key}\n";
        } else {
            $buf .= "$interesting_headers{$key}\n";
        }
    }

    # don't include anything after the first ? in the resource...
    $path =~ /^([^?]*)/;
    $buf .= "/$1";

    # ...unless there is an acl or torrent parameter
    if ($path =~ /[&?]acl($|=|&)/) {
        $buf .= '?acl';
    } elsif ($path =~ /[&?]torrent($|=|&)/) {
        $buf .= '?torrent';
    } elsif ($path =~ /[&?]logging($|=|&)/) {
        $buf .= '?logging';
    } elsif ($path =~ /[&?]location($|=|&)/) {
        $buf .= '?location';
    }

    return $buf;
}

# finds the hmac-sha1 hash of the canonical string and the aws secret access key and then
# base64 encodes the result (optionally urlencoding after that).
sub encode {
    my ($aws_secret_access_key, $str, $urlencode) = @_;
    my $hmac = Digest::HMAC_SHA1->new($aws_secret_access_key);
    $hmac->add($str);
    my $b64 = encode_base64($hmac->digest, '');
    if ($urlencode) {
        return urlencode($b64);
    } else {
        return $b64;
    }
}

sub urlencode {
    my ($unencoded) = @_;
    return uri_escape($unencoded, '^A-Za-z0-9_-');
}

# generates an HTTP::Headers objects given one hash that represents http
# headers to set and another hash that represents an object's metadata.
sub merge_meta {
    my ($headers, $metadata) = @_;
    $headers ||= {};
    $metadata ||= {};

    my $http_header = HTTP::Headers->new;
    while (my ($k, $v) = each %$headers) {
        $http_header->header($k => $v);
    }
    while (my ($k, $v) = each %$metadata) {
        $http_header->header("$METADATA_PREFIX$k" => $v);
    }

    return $http_header;
}

1;
