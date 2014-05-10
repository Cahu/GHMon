package GHMon;

use Carp;
use Dancer qw(:syntax);
use Dancer::Logger::Console;

use RyzomAPI;
use LWP::Simple qw(!get);
use File::Path  qw(make_path);

use Data::Dumper;


our $VERSION = 0.4;

my $CACHE = "cache";


$SIG{__WARN__} = sub {
	carp shift;
};

$SIG{__DIE__} = sub {
	croak shift;
};


my $client = RyzomAPI->new();


sub get_guild {
	my ($apikey) = @_;

	my ($error, $guild, $updated) = $client->guild($apikey);

	info "Server has updated guild info, synchronizing cache..." if ($updated);

	if ($error) {
		warning "Client returned error '$error'";
		return undef;
	}

	if ($updated) {
		info "Updating image cache for key $apikey";
		update_img_cache($apikey, $guild->room);
	}

	return $guild;
}


sub get_character {
	my ($apikey) = @_;

	my ($error, $character, $updated) = $client->character($apikey);

	info "Server has updated character info, synchronizing cache..." if ($updated);

	if ($error) {
		warning "Client returned error '$error'";
		return undef;
	}

	if ($updated) {
		info "Updating image cache for key $apikey";
		update_img_cache($apikey, $character->room);
	}

	return $character;
}


sub update_img_cache {
	my ($apikey, $room) = @_;

	my $dir = "public/$CACHE/$apikey";

	# make sure the cache dir exists
	unless (-d $dir || make_path $dir) {
		warn "Couldn't create cache dir for key $apikey";
		return undef;
	}

	# verify dir permissions
	unless (-r $dir and -w $dir) {
		warn "Couldn't access cache dir for key $apikey";
		return undef;
	}

	# get a list of images before the update
	my %oldfiles;
	$oldfiles{$_} = 0 for (glob("$dir/*.png"));

	for my $item (grep { defined } @$room) {
		my $url   = $client->item_icon($item);
		my $fname = url_to_name($url);
		my $path  = "$dir/$fname";

		if (-r $path) {
			info "$fname already in cache: skipping";
			# notify that this old image is still valid and is to be kept
			$oldfiles{$path} = 1;
			next;
		}

		info "Downloading '$url' to '$path'";
		getstore($url, $path);
	}

	# remove images that are not needed anymore
	for my $path (keys %oldfiles) {
		if ($oldfiles{$path} == 0) {
			unlink $path;
			info "$path is obsolete and has been removed";
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

	forward "/$apikey/inventory";
};

get '/:apikey/inventory' => sub {
	my $apikey = param('apikey');

	my $title;

	if ($apikey =~ /^g/) {
		$title = "Guild Hall";
	}

	elsif ($apikey =~ /^c/) {
		$title = "Apartment";
	}

	else {
		warning "Invalid key: must start by 'g' or 'c'";
		$title = "Error";
	}

	template 'inventory.tt', {
		title    => $title,
		apikey   => $apikey,
		itemlist => [],
	};
};

get '/:apikey/inventory/:what' => sub {
	my $what   = param('what');
	my $apikey = param('apikey');

	my ($thing, $items, $title);

	if ($apikey =~ /^g/) {
		$title = "Guild Hall";
		$thing = get_guild($apikey);
		$items = $thing->room if ($thing);
	}

	elsif ($apikey =~ /^c/) {
		$title = "Apartment";
		$thing = get_character($apikey);
		$items = $thing->room if ($thing);
	}

	else {
		warning "Invalid key: must start by 'g' or 'c'";
		template 'inventory.tt', {
			title  => "Error",
			apikey => $apikey,
			error  => "Invalid key: must start by 'g' or 'c'",
		};
	}

	if (! $items) {
		template 'inventory.tt', {
			title  => "Error",
			apikey => $apikey,
			error  => "Couldn't retrieve any information for key $apikey",
		};
	}

	else {
		if ($what =~ /^\d+$/) {
			my $slot = $what;

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

		elsif ($what eq "mats") {
			template 'inventory.tt', {
				title    => $title,
				apikey   => $apikey,
				itemlist => item_filter(request->host, $apikey, $items, qr/^m/),
			};
		}

		elsif ($what eq "items") {
			template 'inventory.tt', {
				title    => $title,
				apikey   => $apikey,
				itemlist => item_filter(request->host, $apikey, $items, qr/^i/),
			};
		}

		elsif ($what eq "rp") {
			template 'inventory.tt', {
				title    => $title,
				apikey   => $apikey,
				itemlist => item_filter(request->host, $apikey, $items, qr/^rp/),
			};
		}

		else {
			forward "/$apikey/inventory";
		}
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
			{ name => 'raw data' , value => dump_pre($it) },
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
