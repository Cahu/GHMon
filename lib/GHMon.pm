package GHMon;

use Dancer qw(:syntax);
use Dancer::Logger::Console;

use RyzomAPI;
use LWP::Simple qw(!get);

use Data::Dumper;


our $VERSION = 0.1;

my $TITLE = "GHMon";
my $CACHE = "cache";


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



my $client = RyzomAPI->new();


{
	my %cache;

	sub get_guild {
		my ($apikey) = @_;

		my $guild;

		if ($cache{$apikey}) {
			my $time = $client->time;
			my $tick = $time->server_tick;

			my $cached_guild = $cache{$apikey};

			if (!$cached_guild || $cached_guild->cached_until < $tick) {
				info "Refreshing cache for key: $apikey";
				$guild = refresh_cache($apikey);

				if ($guild) {
					$cache{$apikey} = $guild;
					info "Cache update for key $apikey done";
				} else {
					$cache{$apikey} = undef;
					warning "Cache update for key $apikey failed";
				}
			}
			
			else {
				$guild = $cached_guild;
			}
		}

		else {
			info "Initializing cache for key: $apikey";
			$guild = refresh_cache($apikey);

			if ($guild) {
				$cache{$apikey} = $guild;
				info "Cache creation for key $apikey done";
			} else {
				warning "Cache creation for key $apikey failed";
			}
		}


		return $guild;
	}

	sub refresh_cache {
		my ($apikey) = @_;

		my ($error, $guild) = $client->guild($apikey);

		if (! $error) {
			my $dir = "public/$CACHE/$apikey";

			unless (-d $dir) {
				unless (mkdir $dir) {
					warn "Couldn't create cache dir for key $apikey";
					return undef;
				}
			}

			unless (-r $dir and -w $dir) {
				warn "Couldn't access cache dir for key $apikey";
				return undef;
			}

			for my $item (@{ $guild->room }) {
				;
				#getstore(
				#	$client->item_icon($item),
				#	$dir . "/" . sheet_to_name($item)
				#);
			}
		}
		
		else {
			warning Dumper($guild);
		}

		return $guild;
	}

}


unless (-d $CACHE) {
	mkdir $CACHE or die "Can't create cache dir: $!";
}

unless (-r $CACHE and -w $CACHE) {
	die "Can't access cache dir";
}


get '/' => sub {
	my $str = ""
		. $HEADER
		. "Usage: http://server.bla.bla/[guild api key]"
		. $FOOTER
	;

	return $str;
};


get '/:apikey' => sub {
	my $apikey = param('apikey');

	my $str = ""
		. $HEADER
		. "<h2>Home</h2>\n"
		. "<ul>\n"
		. "<li><a href='/$apikey/inventory'>GH's inventory</a></li>\n"
		. "</ul>\n"
		. $FOOTER
	;

	return $str;
};

get '/:apikey/inventory' => sub {
	my $apikey = param('apikey');

	my $str = ""
		. $HEADER
		. "<h2>"
		.    "<a href='/$apikey'>Home</a> > "
		.    "Inventory"
		. "</h2>\n"
		. "<ul>\n"
		. "<li><a href='/$apikey/inventory/items'>Items</a></li>\n"
		. "<li><a href='/$apikey/inventory/mats'>Mats</a></li>\n"
		. "<li><a href='/$apikey/inventory/rp'>RP Items</a></li>\n"
		. "</ul>\n"
	;


	$str .= $FOOTER;
	
	return $str;
};

get '/:apikey/inventory/items' => sub {
	my $apikey = param('apikey');
	my $guild = get_guild($apikey);

	my $str = ""
		. $HEADER
		. "<h2>"
		.    "<a href='/$apikey'>Home</a> > "
		.    "<a href='/$apikey/inventory'>Inventory</a> > "
		.    "Items"
		. "</h2>\n"
		. "<ul>\n"
		. "<li><a href='/$apikey/inventory/mats'>Mats</a></li>\n"
		. "<li><a href='/$apikey/inventory/rp'>RP Items</a></li>\n"
		. "</ul>\n"
	;

	if ($guild) {
		my $items = $guild->room;
		$str .= "<p>\n";
		$str .= item_filter(request->host, $apikey, $items, qr/^i/);
		$str .= "</p>\n";
	} else {
		$str .= "Error retrieving guild from cache."
	}

	return $str;
};

get '/:apikey/inventory/mats' => sub {
	my $apikey = param('apikey');
	my $guild = get_guild($apikey);

	my $str = ""
		. $HEADER
		. "<h2>"
		.    "<a href='/$apikey'>Home</a> > "
		.    "<a href='/$apikey/inventory'>Inventory</a> > "
		.    "Mats"
		. "</h2>\n"
		. "<ul>\n"
		. "<li><a href='/$apikey/inventory/items'>Items</a></li>\n"
		. "<li><a href='/$apikey/inventory/rp'>RP Items</a></li>\n"
		. "</ul>\n"
	;

	if ($guild) {
		my $items = $guild->room;
		$str .= "<p>\n";
		$str .= item_filter(request->host, $apikey, $items, qr/^m/);
		$str .= "</p>\n";
	} else {
		$str .= "Error retrieving guild from cache."
	}

	return $str;
};

get '/:apikey/inventory/rp' => sub {
	my $apikey = param('apikey');
	my $guild = get_guild($apikey);

	my $str = ""
		. $HEADER
		. "<h2>"
		.    "<a href='/$apikey'>Home</a> > "
		.    "<a href='/$apikey/inventory'>Inventory</a> > "
		.    "RP Items"
		. "</h2>\n"
		. "<ul>\n"
		. "<li><a href='/$apikey/inventory/items'>Items</a></li>\n"
		. "<li><a href='/$apikey/inventory/mats'>Mats</a></li>\n"
		. "</ul>\n"
	;

	if ($guild) {
		my $items = $guild->room;
		$str .= "<p>\n";
		$str .= item_filter(request->host, $apikey, $items, qr/^rp/);
		$str .= "</p>\n";
	} else {
		$str .= "Error retrieving guild from cache."
	}

	return $str;
};


sub item_filter {
	my ($host, $apikey, $list_ref, $filter_regex) = @_;

	my @res =
		sort { $a->sheet cmp $b->sheet }
		grep { $_->sheet =~ /$filter_regex/ } @$list_ref;

	my $str = "";

	for (@res) {
		my $title = $_->sheet;
		my $uri   = "http://$host/$CACHE/$apikey/" . sheet_to_name($_);

		$str .= "<img src='$uri' alt='$title' title='$title'>\n";
	}

	return $str;
}

sub sheet_to_name {
	my ($item) = @_;
	return $item->slot . ".png";
}

sub dump_pre {
	my ($var) = @_;
	my $str = "<pre>" . Dumper($var) . "</pre>";
}

1;
