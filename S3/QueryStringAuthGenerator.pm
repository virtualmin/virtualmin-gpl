#!/usr/bin/perl

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

package S3::QueryStringAuthGenerator;

use strict;
use warnings;

use Carp;
use URI::Escape;
use S3 qw($DEFAULT_HOST $PORTS_BY_SECURITY merge_meta);


# This class mimics the interface of AWSAuthConnection, but instead of actually
# performing the operation, this class's methods will return a URL with
# authentication query string parameters which can then be used to perform the
# operation.

# by default, expire in 1 minute.
my $DEFAULT_EXPIRES_IN = 60;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};

    $self->{AWS_ACCESS_KEY_ID} = shift || croak "must specify aws access key id";
    $self->{AWS_SECRET_ACCESS_KEY} = shift || croak "must specify aws secret access key";
    $self->{IS_SECURE}  = shift;
    $self->{IS_SECURE} = 1 if not defined $self->{IS_SECURE};
    $self->{SERVER} = shift || $DEFAULT_HOST;
    $self->{PORT} = shift || $PORTS_BY_SECURITY->{$self->{IS_SECURE}};


    my $protocol = $self->{IS_SECURE} ? 'https' : 'http';

    $self->{URL_BASE} = "$protocol://$self->{SERVER}:$self->{PORT}";
    $self->{EXPIRES_IN} = $DEFAULT_EXPIRES_IN;
    $self->{EXPIRES} = undef;

    bless ($self, $class);
    return $self;
}

sub expires {
    my ($self, $expires) = @_;

    $self->{EXPIRES} = $expires;
    $self->{EXPIRES_IN} = undef;
}

sub expires_in {
    my ($self, $expires_in) = @_;

    $self->{EXPIRES_IN} = $expires_in;
    $self->{EXPIRES} = undef;
}

sub create_bucket {
    my ($self, $bucket, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    $headers ||= {};

    return $self->generate_url('PUT', $bucket, $headers);
}

sub list_bucket {
    my ($self, $bucket, $options, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    $options ||= {};
    $headers ||= {};

    my $path = $bucket;
    if (%$options) {
        $path .= "?" . join('&', map { "$_=" . uri_escape($options->{$_}) } keys %$options)
    }

    return $self->generate_url('GET', $path, $headers);
}

sub delete_bucket {
    my ($self, $bucket, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    $headers ||= {};

    return $self->generate_url('DELETE', "$bucket", $headers);
}

sub put {
    my ($self, $bucket, $key, $object, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless $key;
    $object ||= S3::S3Object->new();
    $headers ||= {};

    $key = uri_escape($key);

    return $self->generate_url('PUT', "$bucket/$key", S3::merge_meta($headers, $object->metadata));
}

sub get {
    my ($self, $bucket, $key, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless $key;
    $headers ||= {};

    $key = uri_escape($key);

    return $self->generate_url('GET', "$bucket/$key", $headers);
}

sub delete {
    my ($self, $bucket, $key, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless $key;
    $headers ||= {};

    $key = uri_escape($key);

    return $self->generate_url('DELETE', "$bucket/$key", $headers);
}

sub get_bucket_logging {
    my ($self, $bucket, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    return $self->generate_url('GET', "$bucket?logging", $headers);
}

sub put_bucket_logging {
    my ($self, $bucket, $logging_xml_doc, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    return $self->generate_url('PUT', "$bucket?logging", $headers);
}

sub get_bucket_acl {
    my ($self, $bucket, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    return $self->get_acl($bucket, "", $headers);
}

sub get_acl {
    my ($self, $bucket, $key, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless defined $key;
    $headers ||= {};

    $key = uri_escape($key);

    return $self->generate_url('GET', "$bucket/$key?acl", $headers);
}

sub put_bucket_acl {
    my ($self, $bucket, $acl_xml_doc, $headers) = @_;
    return $self->put_acl($bucket, '', $acl_xml_doc, $headers);
}

sub put_acl {
    my ($self, $bucket, $key, $acl_xml_doc, $headers) = @_;
    croak 'must specify acl xml document' unless defined $acl_xml_doc;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless defined $key;
    $headers ||= {};

    $key = uri_escape($key);

    return $self->generate_url('PUT', "$bucket/$key?acl", $headers);
}

sub list_all_my_buckets {
    my ($self, $headers) = @_;
    $headers ||= {};

    return $self->generate_url('GET', '', $headers);
}

sub make_bare_url {
    my ($self, $bucket, $key) = @_;

    my $path = $self->{URL_BASE};
    if ($bucket) {
        $path .= "/$bucket";

        if ($key) {
            $path .= "/$key";
        }
    }
    return $path;
}

sub generate_url {
    my ($self, $method, $path, $headers) = @_;
    croak 'must specify method' unless $method;
    croak 'must specify path' unless defined $path;
    $headers ||= {};

    my $expires = 0;
    if ($self->{EXPIRES_IN}) {
        $expires = int(time + $self->{EXPIRES_IN});
    } elsif ($self->{EXPIRES}) {
        $expires = int($self->{EXPIRES});
    } else {
        die 'invalid expires state';
    }

    my $canonical_string = S3::canonical_string($method, $path, $headers, $expires);
    my $encoded_canonical = S3::encode($self->{AWS_SECRET_ACCESS_KEY}, $canonical_string, 1);
    if (index($path, '?') == -1) {
        return "$self->{URL_BASE}/$path?Signature=$encoded_canonical&Expires=$expires&AWSAccessKeyId=$self->{AWS_ACCESS_KEY_ID}";
    } else {
        return "$self->{URL_BASE}/$path&Signature=$encoded_canonical&Expires=$expires&AWSAccessKeyId=$self->{AWS_ACCESS_KEY_ID}";
    }
}

1;
