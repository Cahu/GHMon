package GHMon;

use Carp;
use Dancer qw(:syntax);
use Dancer::Logger::Console;

use RyzomAPI;
use LWP::Simple qw(!get);
use File::Path  qw(make_path);

use Data::Dumper;


our $VERSION = 0.2;

my $TITLE = "GHMon";
my $CACHE = "cache";


$SIG{__WARN__} = sub {
	carp shift;
};

$SIG{__DIE__} = sub {
	croak shift;
};

hook before => sub {
	var title => $TITLE;
};


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

			if ($cached_guild->cached_until < $tick) {
				info "Refreshing cache for key: $apikey";
				$guild = init_cache($apikey);

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
			$guild = init_cache($apikey);

			if ($guild) {
				$cache{$apikey} = $guild;
				info "Cache creation for key $apikey done";
			} else {
				warning "Cache creation for key $apikey failed";
			}
		}

		return $guild;
	}


	sub init_cache {
		my ($apikey) = @_;

		my ($error, $guild) = $client->guild($apikey);

		if (! $error) {
			my $dir = "public/$CACHE/$apikey";

			unless (-d $dir) {
				unless (make_path $dir) {
					warn "Couldn't create cache dir for key $apikey";
					return undef;
				}
			}

			unless (-r $dir and -w $dir) {
				warn "Couldn't access cache dir for key $apikey";
				return undef;
			}

			dl_images($dir, grep { defined } @{ $guild->room });
			return $guild;
		}

		else {
			warning $error;
			return undef;
		}
	}

	sub dl_images {
		my $dir = shift;

		for my $item (@_) {
			my $url   = $client->item_icon($item);
			my $fname = url_to_name($url);

			if (-r "$dir/$fname") {
				info "$fname already in cache: skipping";
				next;
			}

			info "Downloading '$url' to '$dir/$fname'";
			getstore($url, "$dir/$fname");
		}
	}
}


set layout => 'main.tt';

hook before => sub {
	var cache => $CACHE,
};


get '/' => sub {
	my $str = "Usage: http://server.bla.bla/[guild api key]";
	return $str;
};


get '/:apikey' => sub {
	my $apikey = param('apikey');

	my $str = ""
		. "<h2>Home</h2>\n"
		. "<ul>\n"
		. "<li><a href='/$apikey/inventory'>GH's inventory</a></li>\n"
		. "</ul>\n"
	;

	return $str;
};

get '/:apikey/inventory' => sub {
	my $apikey = param('apikey');

	template 'inventory.tt', {
		apikey   => $apikey,
		itemlist => [],
	};
};

get '/:apikey/inventory/items' => sub {
	my $apikey = param('apikey');
	my $guild = get_guild($apikey);

	if ($guild) {
		my $items = $guild->room;
		template 'inventory.tt', {
			apikey   => $apikey,
			itemlist => item_filter(request->host, $apikey, $items, qr/^i/),
		};
	} else {
		template 'inventory.tt', {
			apikey => $apikey,
			error  => "Error retrieving guild from cache.",
		};
	}
};

get '/:apikey/inventory/mats' => sub {
	my $apikey = param('apikey');
	my $guild = get_guild($apikey);

	if ($guild) {
		my $items = $guild->room;
		template 'inventory.tt', {
			apikey   => $apikey,
			itemlist => item_filter(request->host, $apikey, $items, qr/^m/),
		};
	} else {
		template 'inventory.tt', {
			apikey => $apikey,
			error  => "Error retrieving guild from cache.",
		};
	}
};

get '/:apikey/inventory/rp' => sub {
	my $apikey = param('apikey');
	my $guild = get_guild($apikey);

	if ($guild) {
		my $items = $guild->room;
		template 'inventory.tt', {
			apikey   => $apikey,
			itemlist => item_filter(request->host, $apikey, $items, qr/^rp/),
		};
	} else {
		template 'inventory.tt', {
			apikey => $apikey,
			error  => "Error retrieving guild from cache.",
		};
	}
};


get '/:apikey/inventory/:slot' => sub {
	my $slot   = param('slot');
	my $apikey = param('apikey');
	my $guild  = get_guild($apikey);

	unless ($slot =~ /^\d+$/) {
		forward "/$apikey/inventory";
	}

	if ($guild) {
		my $items = $guild->room;
		unless ($slot <= $#$items and defined $items->[$slot]) {
			forward "/$apikey/inventory";
		}

		my $item = $items->[$slot];
		template 'itemdetails.tt', {
			%{ template_item_object($item) },
			details => template_item_details($item), #dump_pre($item),
			apikey  => $apikey,
		};
	}

	else {
		template 'itemdetails.tt', {
			apikey => $apikey,
			error  => "Error retrieving guild from cache.",
		};
	}
};


sub item_filter {
	my ($host, $apikey, $list_ref, $filter_regex) = @_;

	my @filtered =
		sort { $a->sheet cmp $b->sheet }
		grep { defined $_ and $_->sheet =~ /$filter_regex/ } @$list_ref;
	
	my @list;
	for (@filtered) {
		push @list, template_item_object($_);
	}

	return \@list;
}


sub template_item_object {
	my $it = shift;
	my $tar = $client->item_icon($it);

	return {
		slot  => $it->slot,
		title => $it->sheet,
		file  => url_to_name($tar),
	};
}


sub template_item_details {
	my $it = shift;

	if ($it->sheet =~ /^i/) {
		# dealing with item
		return [
			{ name => 'HP'                 , value => $it->hp                                       },
			{ name => 'Weight'             , value => $it->craftparameters->{weight}                },
			{ name => 'Protection factor'  , value => $it->craftparameters->{protectionfactor}      },
			{ name => 'Max vs. smash'      , value => $it->craftparameters->{maxbluntprotection}    },
			{ name => 'Max vs. slash'      , value => $it->craftparameters->{maxslashingprotection} },
			{ name => 'Max vs. pierce'     , value => $it->craftparameters->{maxpiercingprotection} },
			{ name => 'Parry modifier'     , value => $it->craftparameters->{parrymodifier}         },
			{ name => 'Dodge modifier'     , value => $it->craftparameters->{dodgemodifier}         },
		];
	}

	elsif ($it->sheet =~ /^rp/) {
		# dealing with rp item
		return [];
	}

	elsif ($it->sheet =~ /^m/) {
		# dealing with mats
		return [];
	}
}


sub url_to_name {
	my ($url) = @_;

	if ($url =~ /.*sheetid=(.*)/) {
		my $fname = $1;
		$fname =~ tr/&/_/;
		$fname =~ s/=//g;
		$fname .= ".png";
		return $fname;
	}

	return undef;
}


sub dump_pre {
	my ($var) = @_;
	my $str = "<pre>" . Dumper($var) . "</pre>";
}

1;
