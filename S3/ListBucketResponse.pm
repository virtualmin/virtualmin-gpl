#!/usr/bin/perl

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

package S3::ListBucketResponse;

use strict;
use warnings;
use XML::Simple;
use Data::Dumper;

use base qw(S3::Response);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(shift);

    my $doc = XMLin($self->{BODY}, forcearray => ['Contents', 'CommonPrefixes'], suppressempty => 1);
    $self->{ENTRIES} = $doc->{Contents} || [];
    $self->{COMMON_PREFIXES} = $doc->{CommonPrefixes} || [];
    $self->{MARKER} = $doc->{Marker};
    $self->{PREFIX} = $doc->{Prefix};
    $self->{IS_TRUNCATED} = $doc->{IsTruncated} eq 'true';
    $self->{DELIMITER} = $doc->{Delimiter};
    $self->{NAME} = $doc->{Name};
    $self->{MAX_KEYS} = $doc->{MaxKeys};
    $self->{NEXT_MARKER} = $doc->{NextMarker};
    bless ($self, $class);
    return $self;
}

sub entries {
    my ($self) = @_;

    return $self->{ENTRIES};
}

sub common_prefixes {
    my ($self) = @_;

    return $self->{COMMON_PREFIXES};
}

sub marker {
    my ($self) = @_;

    return $self->{MARKER};
}

sub prefix {
    my ($self) = @_;

    return $self->{PREFIX};
}

sub is_truncated {
    my ($self) = @_;

    return $self->{IS_TRUNCATED};
}

sub delimiter {
    my ($self) = @_;

    return $self->{DELIMITER};
}

sub name {
    my ($self) = @_;

    return $self->{NAME};
}

sub max_keys {
    my ($self) = @_;

    return $self->{MAX_KEYS};
}

sub next_marker {
    my ($self) = @_;

    return $self->{NEXT_MARKER};
}

1;
