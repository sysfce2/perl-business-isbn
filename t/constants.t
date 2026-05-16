use Test::More 'no_plan';

my $class = 'Business::ISBN';

subtest 'set up' => sub {
	require_ok $class ;
	can_ok $class, 'import';
	};

subtest 'imports' => sub {
	ok %Business::ISBN::EXPORT_TAGS;
	ok exists $Business::ISBN::EXPORT_TAGS{'all'};
	isa_ok $Business::ISBN::EXPORT_TAGS{'all'}, ref [];
	ok defined $class->import(':all'), 'import returns defiend value';
	};

subtest 'constants' => sub {
	my @c = qw( INVALID_GROUP_CODE INVALID_PUBLISHER_CODE BAD_CHECKSUM GOOD_ISBN BAD_ISBN );
	foreach my $sub (@c) {
		no strict 'refs';
		ok( defined &{$sub}, "Constant '$sub' is defined" );
		}
	};

done_testing();
