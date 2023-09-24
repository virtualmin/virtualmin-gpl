#!/usr/local/bin/perl
# Save domain configuration with input keys,
# excluding keys that start with "submitter" 
# or are empty.

require './virtual-server-lib.pl';
&ReadParse();
my $d = &get_domain($in{'id'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
my @deleted = grep { /^submitter/ || $in{$_} =~ /^$/ } keys %in;
&merge_domain_config($d, \%in, \@deleted);
&lock_domain_name($d->{'dom'});
&save_domain($d);
&unlock_domain_name($d->{'dom'});
&redirect(&get_referer_relative());
