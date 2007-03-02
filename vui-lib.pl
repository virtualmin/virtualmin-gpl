# UI functions specific to Virtualmin

# virtualmin_ui_radio_selector(&opts, name, selected, show-border)
# Returns HTML for a set of radio buttons, each of which shows a different
# block of HTML when selected. &opts is an array ref to arrays containing
# [ value, label, html ]
sub virtualmin_ui_radio_selector
{
return &theme_ui_radio_selector(@_) if (defined(&theme_ui_radio_selector));
local ($opts, $name, $sel, $border) = @_;
local $rv;
if (!$main::ui_radio_selector_donejs++) {
	$rv .= &virtualmin_ui_radio_selector_javascript();
	}
local $optnames =
	"[".join(",", map { "\"".&html_escape($_->[0])."\"" } @$opts)."]";
foreach my $o (@opts) {
	$rv .= &ui_oneradio($name, $o->[0], $o->[1], $sel eq $o->[0],
	    "onClick='selector_show(\"$name\", \"$o->[0]\", $optnames)'");
	}
$rv .= "<br>\n";
foreach my $o (@opts) {
	local $cls = $o->[0] eq $sel ? "selector_shown" : "selector_hidden";
	$rv .= "<div id=sel_${name}_$o->[0] class=$cls>".$o->[2]."</div>\n";
	}
return $rv;
}

sub virtualmin_ui_radio_selector_javascript
{
return <<EOF;
<style>
.selector_shown {display:inline}
.selector_hidden {display:none}
</style>
<script>
function selector_show(name, value, values)
{
for(var i=0; i<values.length; i++) {
	var divobj = document.getElementById('sel_'+name+'_'+values[i]);
	divobj.className = value == values[i] ? 'selector_shown'
					      : 'selector_hidden';
	}
}
</script>
EOF
}



1;

