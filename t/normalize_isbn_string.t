use strict;
use warnings;
use open qw(:std :utf8);

use Test::More;
use List::Util qw(shuffle);

my $class = 'Business::ISBN';
my $method = 'normalize_isbn_string';

my $code_ref;

subtest 'sanity' => sub {
	use_ok $class;
	can_ok $class, $method;

	$code_ref = $class->can($method);
	};

my @table = (
	[ '',           undef, 'enpty string returns undef'     ],
	[ '123',        undef, 'too few chars returns undef'    ],
	[ '123456789A', undef, 'disallowed chars returns undef' ],

	[ ' 123456789X ',             '123456789X', 'spaces stripped' ],
	[ "\r\r\r\n123456789X\n\n\n", '123456789X', 'vertical space stripped' ],

	map {
		my $c = chr(hex($_));
		my $expected = join '', shuffle( 1 .. 9 ), (shuffle(0..9, 'X'))[0];
		my $input = $expected;
		substr $input, 7, 0, $c;
		substr $input, 2, 0, $c;

		[ $input, $expected, sprintf "U+%04X stripped", hex($_) ]
		} ( '2D', 2010 .. 2015, 2212 )
	);

foreach my $row ( @table ) {
	my( $input, $expected, $label ) = @$row;
	subtest "<$input>" => sub {
		is( $code_ref->($input), $expected, $label );
		return unless defined $expected;

		my $isbn_legacy = $class->new( $input );
		isa_ok $isbn_legacy, $class;
		my $isbn_strict = $class->new( $input, { strict => 1 } );
		isa_ok $isbn_strict, $class;
		};
	}

done_testing();
