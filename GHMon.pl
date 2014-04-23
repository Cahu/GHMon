use Dancer;
use Dancer::Logger::Console;

use RyzomAPI;
use Data::Dumper;

my $TITLE = "GHMon";

my $HEADER = <<HTML;
<!DOCTYPE html>
<html>
<head>
<title>$TITLE</title>
</head>
<body>
<h1>GHMon!</h1>
HTML

my $FOOTER = <<HTML;
</body>
</html> 
HTML


set 'logger'       => 'console';
set 'log'          => 'debug';
set 'show_errors'  => 1;
set 'startup_info' => 1;
set 'warnings'     => 1;

my $client = RyzomAPI->new();


{
	my %cache;

	sub get_guild {
		my ($apikey) = @_;

		my $error;

		if ($cache{$apikey}) {
			my $time = $client->time;
			my $tick = $time->server_tick;

			my $cached_guild = $cache{$apikey};

			if (!$cached_guild || $cached_guild->cached_until < $tick) {
				# refresh
				info "Refreshing cache";
				($error, $cache{$apikey}) = $client->guild($apikey);
			}
		}

		else {
			info "Initializing cache";
			($error, $cache{$apikey}) = $client->guild($apikey);
		}

		return ($error, $cache{$apikey});
	}
}


get '/:apikey' => sub {
	my $apikey = param('apikey');

	my ($error, $guild) = get_guild($apikey);

	my $str = ""
		. $HEADER
		. "<h2>Home</h2>\n"
	;

	if ($error) {
		$str .= dump_pre($error)
	}

	else {
		$str .= ""
			. "<ul>\n"
			. "<li><a href='/$apikey/inventory'>GH's inventory</a></li>\n"
			. "</ul>\n"
		;
	}

	$str .= $FOOTER;
	
	return $str;
};

get '/:apikey/inventory' => sub {
	my $apikey = param('apikey');

	my ($error, $guild) = get_guild($apikey);

	my $str = ""
		. $HEADER
		. "<h2><a href='/$apikey'>Home</a> > Inventory</h2>\n"
	;

	if ($error) {
		$str .= dump_pre($error)
	}

	else {
		my $items = $guild->room;
		$str .= "<p>";
		for (sort { $a->sheet cmp $b->sheet } @$items) {
			my $title = $_->sheet;
			my $url   = $client->item_icon($_);
			$str .= "<img src='$url' alt='icon' title='$title'>\n";
		}
		$str .= "</p>";
	}

	$str .= $FOOTER;
	
	return $str;
};

dance;


sub item_filter {
	my ($list_ref, $filter_regex) = @_;

	my @res =
		sort { $a->sheet cmp $b->sheet }
		grep { $_->sheet =~ /$filter_regex/ } @$list_ref;

	my $str = "";

	for (@res) {
		my $title = $_->sheet;
		my $uri   = $client->item_icon($_);

		$str .= "<img src='$uri' alt='$title' title='$title'>\n";
	}

	return $str;
}

sub dump_pre {
	my ($var) = @_;
	my $str = "<pre>" . Dumper($var) . "</pre>";
}
