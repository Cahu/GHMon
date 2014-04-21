use Dancer;

my $TITLE = "GHMon";

my $HEADER = <<HTML;
<!DOCTYPE html>
<html>
<head>
<title>$TITLE</title>
</head>
<body>
HTML

my $FOOTER = <<HTML;
</body>
</html> 
HTML

get '/' => sub {
	return
		  $HEADER
		. "Hello, World!\n"
		. $FOOTER
	;
};

dance;
