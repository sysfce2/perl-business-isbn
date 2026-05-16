use strict;

use Test::More 'no_plan';

my $class = 'Business::ISBN';
my $class_10 = $class . '10';
my $class_13 = $class . '13';

my $GOOD_ISBN          = "0596527241";
my $GOOD_ISBN_STRING   = "0-596-52724-1";

my $GOOD_EAN           = "9780596527242";
my $GOOD_EAN_STRING    = "978-0-596-52724-2";

my $GROUP              = "English";

my $PREFIX             = '978';

my $GROUP_CODE         = "0";
my $PUBLISHER          = "596";

my $BAD_CHECKSUM_ISBN  = "0596527244";

my $BAD_GROUP_ISBN     = "9990022576";

my $BAD_PUBLISHER_ISBN = "9165022222"; # 91-650-22222-?  Sweden (stops at 649)

my $NULL_ISBN          = undef;

my $NO_GOOD_CHAR_ISBN  = "abcdefghij";

my $SHORT_ISBN         = "156592";

subtest 'sanity' => sub {
	use_ok $class;
	can_ok $class, qw(new as_isbn13 as_isbn10);
	};

subtest 'new' => sub {
	my $isbn = $class->new( $GOOD_ISBN );
	isa_ok $isbn, $class;
	isa_ok $isbn, $class_10;

	is $isbn->is_valid,       $class->GOOD_ISBN, "$GOOD_ISBN is valid";

	is $isbn->type,           'ISBN10',          "$GOOD_ISBN has right type";

	is $isbn->prefix,         '',                "$GOOD_ISBN has right prefix";
	is $isbn->publisher_code, $PUBLISHER,        "$GOOD_ISBN has right publisher";
	is $isbn->group_code,     $GROUP_CODE,       "$GOOD_ISBN has right country code";
	like $isbn->group,        qr/\Q$GROUP/,      "$GOOD_ISBN has right country";
	is $isbn->as_string,      $GOOD_ISBN_STRING, "$GOOD_ISBN stringifies correctly";
	is $isbn->as_string([]),  $GOOD_ISBN,        "$GOOD_ISBN stringifies correctly";

	is $isbn->as_string([]),  $isbn->common_data, "$GOOD_ISBN stringifies correctly";
	};

subtest 'clone' => sub {
	my $isbn = $class->new( $GOOD_ISBN );
	isa_ok $isbn, $class;
	isa_ok $isbn, $class_10;

	my $clone = $isbn->as_isbn10;
	isa_ok $clone, $class_10;
	is $clone->is_valid,       $class->GOOD_ISBN, "$GOOD_ISBN is valid";

	is $clone->publisher_code, $PUBLISHER,        "$GOOD_ISBN has right publisher";
	is $clone->group_code,     $GROUP_CODE,       "$GOOD_ISBN has right country code";
	like $clone->group,        qr/\Q$GROUP/,      "$GOOD_ISBN has right country";
	is $clone->as_string,      $GOOD_ISBN_STRING, "$GOOD_ISBN stringifies correctly";
	is $clone->as_string([]),  $GOOD_ISBN,        "$GOOD_ISBN stringifies correctly";
	};

subtest 'isbn13' => sub {
	my $isbn = $class->new( $GOOD_ISBN );
	isa_ok $isbn, $class;
	isa_ok $isbn, $class_10;

	my $isbn13 = $isbn->as_isbn13;
	isa_ok $isbn13, $class;
	isa_ok $isbn13, $class_13;

	is $isbn13->is_valid,       $class->GOOD_ISBN, "$GOOD_ISBN is valid";

	is $isbn13->type,           'ISBN13',          "$GOOD_ISBN has right type";
	is $isbn13->prefix,         $PREFIX,           "$GOOD_ISBN has right prefix";
	is $isbn13->publisher_code, $PUBLISHER,        "$GOOD_ISBN has right publisher";
	is $isbn13->group_code,     $GROUP_CODE,       "$GOOD_ISBN has right country code";
	like $isbn13->group,        qr/\Q$GROUP/,      "$GOOD_ISBN has right country";
	is $isbn13->as_string,      $GOOD_EAN_STRING,  "$GOOD_ISBN stringifies correctly";
	is $isbn13->as_string([]),  $GOOD_EAN,         "$GOOD_ISBN stringifies correctly";
	};

subtest 'bad checksums' => sub {
	my $isbn = $class->new( $BAD_CHECKSUM_ISBN );
	isa_ok $isbn, $class;
	isa_ok $isbn, $class_10;

	is $isbn->error, $class->BAD_CHECKSUM, "Bad checksum [$BAD_CHECKSUM_ISBN] is invalid";
	is $isbn->input_isbn, $BAD_CHECKSUM_ISBN, "Bad ISBN is in input_data";

	#after this we should have a good ISBN
	$isbn->fix_checksum;
	ok $isbn->is_valid, "Bad checksum [$BAD_CHECKSUM_ISBN] had checksum fixed";
	is $isbn->input_isbn, $BAD_CHECKSUM_ISBN, "Bad ISBN is still in input_data";
	};

subtest 'bad country code' => sub {
	my $isbn = $class->new( $BAD_GROUP_ISBN );
	isa_ok $isbn, $class_10;
	is $isbn->error, $class->INVALID_GROUP_CODE, "Bad group code [$BAD_GROUP_ISBN] is invalid";
	};

subtest 'bad publisher code' => sub {
	my $isbn = $class->new( $BAD_PUBLISHER_ISBN );
	isa_ok $isbn, $class_10;
	is $isbn->error, $class->INVALID_PUBLISHER_CODE, "Bad publisher [$BAD_PUBLISHER_ISBN] is invalid";
	};

subtest 'convert to EAN' => sub {
	my $isbn = $class->new( $GOOD_ISBN );
	is $isbn->as_isbn13->as_string([]), $GOOD_EAN, "$GOOD_ISBN converted to EAN";
	};

subtest 'prevent bad things' => sub {
	my $isbn = $class->new( $GOOD_ISBN );
	my $result = eval { $isbn->_set_prefix( '978' ) };
	ok defined $@, "Setting prefix on ISBN-10 fails";
	};

subtest 'good ISBNs' => sub {
	my $file = "isbns.txt";

	open my $fh, $file or do {
		diag "Could not read <$file>: $!";
		fail();
		return;
		};
	diag "\nChecking ISBNs... (this may take a bit)";

	my $legacy_bad = 0;
	my $strict_bad = 0;
	while( <$fh> ) {
		chomp;
		my $isbn_legacy = $class->new($_);
		unless( defined $isbn_legacy and $isbn_legacy->is_valid ) {
			diag "Good ISBN <$_> was not valid in legacy rules";
			$legacy_bad++ unless $isbn_legacy->is_valid;
			}

		my $isbn_strict = $class->new($_, {strict=>1});
		unless( defined $isbn_strict and $isbn_strict->is_valid ) {
			diag "Good ISBN <$_> was not valid in strict rules";
			$strict_bad++ unless $isbn_strict->is_valid;
			}
		}

	ok $legacy_bad == 0, "Match good ISBNs with legacy rules";
	ok $strict_bad == 0, "Match good ISBNs with strict rules";
	};

subtest 'bad ISBNs' => sub {
	my $file = "bad-isbns.txt";

	open my $fh, $file or do {
		diag "Could not read <$file>: $!";
		fail();
		return;
		};
	diag "\nChecking bad ISBNs... (this should be fast)";

	my $legacy_good = 0;
	my $strict_good = 0;
	while( <$fh> ) {
		chomp;
		my $isbn_legacy = $class->new($_);
		if( defined $isbn_legacy and $isbn_legacy->is_valid ) {
			diag "Bad ISBN <$_> was valid in legacy rules";
			$legacy_good++ unless $isbn_legacy->is_valid;
			}

		my $isbn_strict = $class->new($_, {strict=>1});
		if( defined $isbn_legacy and $isbn_strict->is_valid ) {
			diag "Bad ISBN <$_> was valid in strict rules";
			$strict_good++ unless $isbn_strict->is_valid;
			}
		}

	ok $legacy_good == 0, "Match bad ISBNs with legacy rules";
	ok $strict_good == 0, "Match bad ISBNs with strict rules";
	};

done_testing();
