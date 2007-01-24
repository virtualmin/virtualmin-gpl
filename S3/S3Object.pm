#!/usr/bin/perl

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

package S3::S3Object;

use strict;
use warnings;


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    $self->{DATA} = shift;
    $self->{METADATA} = shift || {};
    bless ($self, $class);
    return $self;
}

sub data {
    my ($self) = @_;

    return $self->{DATA};
}

sub metadata {
    my ($self) = @_;

    return $self->{METADATA};
}

1;
