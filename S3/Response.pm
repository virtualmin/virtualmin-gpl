#!/usr/bin/perl

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

use strict;
use warnings;

package S3::Response;

use Carp;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    $self->{HTTP_RESPONSE} = shift || croak "must specify http response";
    $self->{BODY} = $self->{HTTP_RESPONSE}->content;
    bless ($self, $class);
    return $self;
}

sub http_response {
    my ($self) = @_;
    return $self->{HTTP_RESPONSE};
}

sub body {
    my ($self) = @_;
    return $self->{BODY};
}

1;
