#!/usr/bin/perl
use strict;

use Test::More;


my @classes = map { "Business::ISBN$_" } '',  '10', '13';

my @methods = qw(
	as_isbn10
	as_isbn13
	_set_prefix
	_set_type
	_hyphen_positions
	);

foreach my $class ( @classes ) {
	subtest $class => sub {
		use_ok $class;
		can_ok $class, @methods;
		};
	}

done_testing();
