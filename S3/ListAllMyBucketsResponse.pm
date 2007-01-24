#!/usr/bin/perl

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

package S3::ListAllMyBucketsResponse;

use strict;
use warnings;

use XML::Simple;
use Data::Dumper;

use base qw(S3::Response);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(shift);

    my $doc = XMLin($self->{BODY}, forcearray => ['Bucket']);
    $self->{ENTRIES} = $doc->{Buckets}{Bucket} || [];

    bless ($self, $class);
    return $self;
}

sub entries {
    my ($self) = @_;

    return $self->{ENTRIES};
}

1;
