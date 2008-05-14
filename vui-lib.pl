# UI functions specific to Virtualmin

# virtualmin_ui_rating_selector(name, value, max, cgi)
# Returns HTML for a field for selecting a rating for something. When chosen,
# submits to the given CGI.
sub virtualmin_ui_rating_selector
{
return &theme_virtualmin_ui_rating_selector(@_)
	if (defined(&theme_virtualmin_ui_rating_selector));
local ($name, $value, $max, $cgi) = @_;
$value ||= 0;
local $rv;
if (!$main::done_virtualmin_ui_rating_selector++) {
	# Generate highlighting Javascript code
	$rv .= &virtualmin_ui_rating_selector_javascript();
	}
for($i=1; $i<=$max; $i++) {
	local $img = $i <= $value ? "staron.gif" : "staroff.gif";
	if ($cgi) {
		local $cgiv = $cgi;
		$cgiv .= ($cgi =~ /\?/ ? "&" : "?");
		$cgiv .= $name."=".$i;
		$rv .= "<a href='$cgiv' id=$name$i ".
#		  "onMouseOver='rating_selector_entry(\"$name\", $i, $max)' ".
#		  "onMouseOut='rating_selector_exit(\"$name\", $value, $max)' ".
		  "><img src=images/$img border=0></a>";
		}
	else {
		$rv .= "<img src=images/$img>";
		}
	}
return $rv;
}

sub virtualmin_ui_rating_selector_javascript
{
return <<EOF;
<script>
// Highlight this star and others before it
function rating_selector_entry(name, idx, max)
{
for(i=1; i<=max; i++) {
   obj = document.getElementById(name+i);
   if (obj) {
     img = i <= idx ? 'starover.gif' : 'staroff.gif';
     obj.innerHTML = '<img src=images/'+img+' border=0>';
     }
   }
}

// Returns all stars to default
function rating_selector_exit(name, value, max)
{
for(i=1; i<=max; i++) {
   obj = document.getElementById(name+i);
   if (obj) {
     img = i <= value ? 'staron.gif' : 'staroff.gif';
     obj.innerHTML = '<img src=images/'+img+' border=0>';
     }
   }
}
</script>
EOF
}

# virtualmin_ui_apply_radios([tag])
# Returns Javascript to fake a click on all radio buttons on a form, to make
# them perform any onClick actions
sub virtualmin_ui_apply_radios
{
local ($tag) = @_;
local $rv = <<EOF;
for(i=0; i<document.forms.length; i++) {
  form = document.forms[i];
  for(j=0; j<form.elements.length; j++) {
    e = form.elements[j];
    if (e.type == "radio") {
      if (e.checked && !e.done_click) {
        e.done_click = 1;
        e.click();
        }
      }
    }
  }
EOF
$rv =~ s/\n/ /g;
return $tag ? "$tag='$rv'" : $rv;
}

# Temporary compatability function
sub virtualmin_ui_hr
{
if (defined(&ui_hr()) {
	return &ui_hr();
	}
else {
	return "<hr>\n";
	}
}

1;

