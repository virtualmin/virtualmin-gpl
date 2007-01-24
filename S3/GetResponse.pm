#!/usr/bin/perl

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

package S3::GetResponse;

use strict;
use warnings;

use base qw(S3::Response);
use Carp;
use S3 qw($METADATA_PREFIX);
use S3::S3Object;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(shift);

    my $headers = $self->{HTTP_RESPONSE}->headers;
    my $metadata = _get_aws_metadata($headers);

    $self->{OBJECT} = S3::S3Object->new($self->{BODY}, $metadata);

    bless ($self, $class);
    return $self;
}

sub object {
    my ($self) = @_;

    return $self->{OBJECT};
}

sub _get_aws_metadata {
    my ($headers) = @_;
    croak "must specify headers" unless $headers;

    my $metadata = {};
    foreach my $key (%$headers) {
        my $lk = lc $key;
        if ($lk =~ /^$METADATA_PREFIX/) {
            $metadata->{substr($key, length($METADATA_PREFIX))} = $headers->{$key};
        }
    }

    return $metadata;
}

1;
