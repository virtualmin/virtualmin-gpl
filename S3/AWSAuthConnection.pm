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
use Digest::MD5;

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
    my @rv;
    my $pos = undef;
    my $maxkeys = 1000;

    my $response;
    while(1) {
	    my $path = $bucket;
	    my %o = %$options;
	    if ($pos) {
		$o{'marker'} = $pos;
	    }
	    $o{'max-keys'} = $maxkeys;
	    if (%o) {
		$path .= "?".join('&', map { "$_=".urlencode($o{$_}) } keys %o)
	    }

	    my $r = S3::ListBucketResponse->new(
		$self->_make_request('GET', $path, $headers));
	    if ($r->http_response->code != 200) {
		return $r;
	    }
	    if ($response) {
		# Add to existing response
		push(@{$response->entries}, @{$r->entries});
	    } else {
		# This is the first response
		$response = $r;
	    }
	    last if (!@{$r->entries});			  # No more to get
	    last if (!$pos && @{$r->entries} < $maxkeys); # Got less than 1000,
							  # no need to go on
	    $pos = $r->entries->[@{$r->entries} - 1]->{'Key'};
	}
   return $response;
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
      my $doc = XMLin($rv->{BODY}, ForceArray => 1);
      $rv->{'AccessControlPolicy'} = $doc;
    }
    return $rv;
}

sub get_bucket_lifecycle {
    my ($self, $bucket, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    $headers ||= {};

    my $rv = S3::GetResponse->new($self->_make_request('GET', "$bucket?lifecycle", $headers));
    if ($rv->http_response->code == 200) {
      my $doc = XMLin($rv->{BODY}, ForceArray => 1);
      $rv->{'LifecycleConfiguration'} = $doc;
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

sub put_bucket_lifecycle {
    my ($self, $bucket, $lifecycle_xml_doc, $headers) = @_;
    croak 'must specify lifecycle xml document' unless defined $lifecycle_xml_doc;
    croak 'must specify bucket' unless $bucket;
    $headers ||= {};
    my $digest = Digest::MD5::md5_base64($lifecycle_xml_doc);
    while(length($digest) % 4) {
	$digest .= "=";
	}
    $headers->{'Content-MD5'} = $digest;
    return S3::Response->new(
        $self->_make_request('PUT', "$bucket/?lifecycle", $headers, $lifecycle_xml_doc));
}

sub abort_upload {
    my ($self, $bucket, $key, $uploadid, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless $key;
    croak 'must specify uploadid' unless $uploadid;
    $headers ||= {};

    return S3::Response->new(
        $self->_make_request('DELETE', "$bucket/$key?uploadId=$uploadid",
			     $headers));
}

sub complete_upload {
    my ($self, $bucket, $key, $uploadid, $tags, $headers) = @_;
    croak 'must specify bucket' unless $bucket;
    croak 'must specify key' unless $key;
    croak 'must specify uploadid' unless $uploadid;
    $headers ||= {};

    my $tags_xml;
    $tags_xml = "<CompleteMultipartUpload>\n";
    for(my $i=1; $i<=@$tags; $i++) {
 	$tags_xml .= "<Part>\n".
		     "<PartNumber>".$i."</PartNumber>\n".
		     "<ETag>".$tags->[$i-1]."</ETag>\n".
		     "</Part>\n";
    }
    $tags_xml .= "</CompleteMultipartUpload>\n";

    $headers->{'Content-Length'} = length($tags_xml);
    return S3::Response->new(
        $self->_make_request('POST', "$bucket/$key?uploadId=$uploadid",
			     $headers, $tags_xml));
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
	$self->{SERVER_REDIRECTS} ||= 0;
	$self->{SERVER_REDIRECTS}++;
	my $newpath = $path;
	if ($self->{'SERVER_REDIRECTS'} == 1) {
		# Redirecting from default to new endpoint. Remove the leading
		# path element.
		$newpath =~ s/^([^\/\?]+)//;
		if ($newpath eq "") {
		  # When requesting a bucket like /foo originally, we have to
		  # request ? from foo.s3.amazonaws.com instead. HOWEVER, the
		  # path to sign is still like /foo/
		  $newpath = "?";
		  $path .= "/";
		} elsif ($newpath =~ /^\?/) {
		  # When requesting a bucket like /foo?marker=smeg originally,
		  # a / is needed at the end of the bucket
		  $path =~ s/\?/\/\?/;
		}
		# If the new path ends up like /bar.com.tar.gz, it must be
		# converted to bar.com.tar.gz for the HTTP request
		$newpath =~ s/^\///;
		}
	else {
		# Already redirected once, so only need to change server
		$path = $authpath;
		}
        $response = $self->_make_request($method, $newpath, $headers,
					 $data, $metadata, $path);
	$self->{SERVER} = $oldserver;
	$self->{SERVER_REDIRECTS}--;
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
