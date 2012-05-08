#!/usr/bin/perl

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

package S3::AWSAuthConnection;

use strict;
use warnings;

use HTTP::Date;
use URI::Escape;
use Carp;
use XML::Simple;

use S3 qw($DEFAULT_HOST $PORTS_BY_SECURITY merge_meta urlencode);
use S3::GetResponse;
use S3::ListBucketResponse;
use S3::ListAllMyBucketsResponse;
use S3::S3Object;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    $self->{AWS_ACCESS_KEY_ID} = shift || croak "must specify aws access key id";
    $self->{AWS_SECRET_ACCESS_KEY} = shift || croak "must specify aws secret access key";
    $self->{IS_SECURE} = shift;
    $self->{IS_SECURE} = 1 if (not defined $self->{IS_SECURE});
    $self->{SERVER} = shift || $DEFAULT_HOST;
    $self->{PORT} = shift || $PORTS_BY_SECURITY->{$self->{IS_SECURE}};
    $self->{AGENT} = LWP::UserAgent->new();
    bless ($self, $class);
    return $self;
}

sub create_bucket {
    my ($self, $bucket, $headers, $data) = @_;
    croak 'must specify bucket' unless $bucket;
    $headers ||= {};

    return S3::Response->new(
	$self->_make_request('PUT', $bucket, $headers, $data));
}

sub list_bucket {
    my ($self, $bucket, $options, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    $options ||= {};
    $headers ||= {};

    my $path = $bucket;
    if (%$options) {
        $path .= "?" . join('&', map { "$_=" . urlencode($options->{$_}) } keys %$options)
    }

    return S3::ListBucketResponse->new($self->_make_request('GET', $path, $headers));
}

sub delete_bucket {
    my ($self, $bucket, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    $headers ||= {};

    return S3::Response->new($self->_make_request('DELETE', $bucket, $headers));
}

sub put {
    my ($self, $bucket, $key, $object, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless $key;
    $headers ||= {};

    $key = urlencode($key);

    if (ref($object) ne 'S3::S3Object') {
        $object = S3::S3Object->new($object);
    }

    return S3::Response->new($self->_make_request('PUT', "$bucket/$key", $headers, $object->data, $object->metadata));
}

sub get {
    my ($self, $bucket, $key, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless $key;
    $headers ||= {};

    $key = urlencode($key);

    return S3::GetResponse->new($self->_make_request('GET', "$bucket/$key", $headers));
}

sub delete {
    my ($self, $bucket, $key, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless $key;
    $headers ||= {};

    $key = urlencode($key);

    return S3::Response->new($self->_make_request('DELETE', "$bucket/$key", $headers));
}

sub get_bucket_logging {
    my ($self, $bucket, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    my $rv = S3::GetResponse->new($self->_make_request('GET', "$bucket?logging", $headers));
    if ($rv->http_response->code == 200) {
      my $doc = XMLin($rv->{BODY});
      $rv->{'LoggingPolicy'} = $doc;
    }
    return $rv;
}

sub put_bucket_logging {
    my ($self, $bucket, $logging_xml_doc, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    return S3::Response->new($self->_make_request('PUT', "$bucket?logging", $headers, $logging_xml_doc));
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

    $key = urlencode($key);

    my $rv = S3::GetResponse->new($self->_make_request('GET', "$bucket/$key?acl", $headers));
    if ($rv->http_response->code == 200) {
      my $doc = XMLin($rv->{BODY});
      $rv->{'AccessControlPolicy'} = $doc;
    }
    return $rv;
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

    $key = urlencode($key);

    return S3::Response->new(
        $self->_make_request('PUT', "$bucket/$key?acl", $headers, $acl_xml_doc));
}

sub list_all_my_buckets {
    my ($self, $headers) = @_;
    $headers ||= {};

    return S3::ListAllMyBucketsResponse->new($self->_make_request('GET', '', $headers));
}

sub get_bucket_location {
    my ($self, $bucket, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    $headers ||= {};

    my $rv = S3::GetResponse->new($self->_make_request('GET', "$bucket?location", $headers));
    if ($rv->http_response->code == 200) {
      my $doc = XMLin($rv->{BODY});
      $rv->{'LocationConstraint'} = $doc->{'content'};
    }
    return $rv;
}

sub _make_request {
    my ($self, $method, $path, $headers, $data, $metadata, $authpath) = @_;
    $authpath ||= $path;
    croak 'must specify method' unless $method;
    croak 'must specify path' unless defined $path;
    $headers ||= {};
    $data ||= '';
    $metadata ||= {};

    my $http_headers = merge_meta($headers, $metadata);

    $self->_add_auth_header($http_headers, $method, $authpath);
    my $protocol = $self->{IS_SECURE} ? 'https' : 'http';
    my $url = "$protocol://$self->{SERVER}:$self->{PORT}/$path";
    my $request = HTTP::Request->new($method, $url, $http_headers);
    $request->content($data);
    my $response = $self->{AGENT}->request($request);
    if ($response->code >= 300 && $response->code < 400) {
      # S3 redirect .. read the new endpoint from the content
      if ($response->content =~ /<Endpoint>([^<]*)<\/Endpoint>/i) {
	my $oldserver = $self->{SERVER};
	$self->{SERVER} = $1;
	my $newpath = $path;
	$newpath =~ s/^([^\/]+)//;
	if ($newpath eq "") {
	  # When requesting a bucket like /foo originally, we have to
	  # request ? from foo.s3.amazonaws.com instead. HOWEVER, the path
	  # to sign is still like /foo/
	  $newpath = "?";
	  $path .= "/";
	}
	# If the new path ends up like /bar.com.tar.gz, it must be converted
	# to bar.com.tar.gz for the HTTP request
        $newpath =~ s/^\///;
        $response = $self->_make_request($method, $newpath, $headers,
					 $data, $metadata, $path);
	$self->{SERVER} = $oldserver;
      }
    }
    return $response;
}

sub _add_auth_header {
    my ($self, $headers, $method, $path) = @_;

    if (not $headers->header('Date')) {
        $headers->header(Date => time2str(time));
    }
    if (not $headers->header('Host')) {
        $headers->header(Host => $self->{SERVER});
    }
    my $canonical_string = S3::canonical_string($method, $path, $headers);
    my $encoded_canonical = S3::encode($self->{AWS_SECRET_ACCESS_KEY}, $canonical_string);
    $headers->header(Authorization => "AWS $self->{AWS_ACCESS_KEY_ID}:$encoded_canonical");
}

1;
