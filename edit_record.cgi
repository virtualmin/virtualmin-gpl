#!/usr/local/bin/perl
# Show a form for creating or editing a DNS record

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&require_bind();

if ($in{'type'}) {
	# Adding a new record
	if ($in{'type'} eq '$ttl') {
		$r = { 'defttl' => '1h' };
		}
	else {
		$r = { 'type' => $in{'type'},
		       'name' => ".".$d->{'dom'}."." };
		}
	&ui_print_header(&domain_in($d), $text{'record_title1'}, "");
	}
else {
	# Editing existing one
	($recs, $file) = &get_domain_dns_records_and_file($d);
	$file || &error($recs);
	($r) = grep { $_->{'id'} eq $in{'id'} } @$recs;
	$r || &error($text{'record_egone'});
	$r->{'defttl'} ||
	    $r->{'name'} eq $d->{'dom'}."." ||
	    $r->{'name'} =~ /\.\Q$d->{'dom'}\E\.$/ ||
		&error(&text('record_eunder', $r->{'name'}, $d->{'dom'}));
	&ui_print_header(&domain_in($d), $text{'record_title2'}, "");
	}

# Get type, verify editability
if ($r->{'defttl'}) {
	$t = { 'type' => '$ttl',
	       'desc' => $text{'records_typedefttl'} };
	}
else {
	($t) = grep { $_->{'type'} eq $r->{'type'} } &list_dns_record_types($d);
	}
&can_edit_record($d, $r) && $t || &error($text{'record_eedit'});

print &ui_form_start("save_record.cgi", "post");
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("type", $in{'type'});
print &ui_hidden("id", $in{'id'});
print &ui_table_start($text{'record_header'}, undef, 2);

# Record name
if ($r->{'defttl'}) {
	# Default TTL has no name!
	}
elsif ($in{'type'} && $t->{'domain'}) {
	# New record, might be same as domain, or within it
	print &ui_table_row($text{'record_name'},
			    &ui_radio("name_def", 0,
				      [ [ 1, $text{'record_same'} ],
					[ 0, " " ] ]).
			    &ui_textbox("name", undef, 20).
			    "<tt>.$d->{'dom'}</tt>");
	}
elsif ($r->{'name'} eq $d->{'dom'}.".") {
	# Same as domain - disallow changes
	$name = $r->{'name'};
	$name =~ s/\.$//;
	print &ui_table_row($text{'record_name'},
			    "<tt>$name</tt>");
	}
else {
	# Within the domain
	$r->{'name'} =~ /^(\S*)\.\Q$d->{'dom'}\E\.$/ ||
		&error($text{'record_eparse'});
	$name = $1;
	print &ui_table_row($text{'record_name'},
			    &ui_textbox("name", $name, 20).
			    "<tt>.$d->{'dom'}</tt>");
	}

# Record type
print &ui_table_row($text{'record_type'}, $t->{'type'}." - ".$t->{'desc'});

if ($r->{'defttl'}) {
	# Default TTL for domain
	print &ui_table_row($text{'record_defttl'},
		&ttl_field("defttl", $r->{'defttl'}));
	}
else {
	# TTL for record
	print &ui_table_row($text{'record_ttl'},
		&ui_radio("ttl_def", $r->{'ttl'} ? 0 : 1,
			  [ [ 1, $text{'record_ttl1'} ],
			    [ 0, $text{'record_ttl0'} ] ])." ".
		&ttl_field("ttl", $r->{'ttl'}));

	# Values (type specific)
	@vals = @{$t->{'values'}};
	for(my $i=0; $i<@vals; $i++) {
		print &ui_table_row($vals[$i]->{'desc'},
			&ui_textbox("value_$i", $r->{'values'}->[$i],
				    $vals[$i]->{'size'})." ".
			$vals[$i]->{'suffix'});
		}
	}

# Record comment
print &ui_table_row($text{'record_comment'},
		    &ui_textbox("comment", $r->{'comment'}, 60));

print &ui_table_end();
if ($in{'type'}) {
	print &ui_form_end([ [ undef, $text{'create'} ] ]);
	}
elsif (&can_delete_record($d, $r)) {
	print &ui_form_end([ [ undef, $text{'save'} ],
			     [ 'delete', $text{'delete'} ] ]);
	}
else {
	print &ui_form_end([ [ undef, $text{'save'} ] ]);
	}

&ui_print_footer("list_records.cgi?dom=$in{'dom'}", $text{'records_return'},
	         &domain_footer_link($d),
		 "", $text{'index_return'});

# ttl_field(name, value)
# Returns a field for entering a TTL
sub ttl_field
{
local ($name, $ttl) = @_;
local $ttl_units;
if ($ttl =~ /^(\d+)([a-z])$/i) {
	$ttl = $1;
	$ttl_units = lc($2);
	}
else {
	$ttl_units = "s";
	}
return &ui_textbox($name, $ttl, 5)." ".
	&ui_select($name."_units", $ttl_units || "s",
		   [ [ "s", $bind8::text{'seconds'} ],
		     [ "m", $bind8::text{'minutes'} ],
		     [ "h", $bind8::text{'hours'} ],
		     [ "d", $bind8::text{'days'} ],
		     [ "w", $bind8::text{'weeks'} ] ], 1, 0, 1);
}
