use strict;
use warnings;
use open qw(:std :utf8);

use Test::More;
use List::Util qw(shuffle);

my $class = 'Business::ISBN';
my $method = 'new';

subtest 'sanity' => sub {
	use_ok $class;
	can_ok $class, $method;
	};

# this should fail for both
my $trial_isbn = "X";

subtest 'trial fails otherwise' => sub {
	subtest 'legacy' => sub {
		my $isbn = $class->new($trial_isbn);
		is $isbn, undef, "<$trial_isbn> fails with legacy mode";
		};

	subtest 'strict' => sub {
		my $isbn = $class->new($trial_isbn, {strict=>1});
		is $isbn, undef, "<$trial_isbn> fails with strict mode";
		};

	subtest 'callback returns nothing' => sub {
		my $normalizer = sub { return };
		my $isbn = $class->new($trial_isbn, {strict=>1, normalizer => $normalizer});
		is $isbn, undef, 'ISBN is bad';
		};

	};

subtest 'normalizers' => sub {
	subtest 'callback returns good ISBN' => sub {
		my $normalizer = sub { "0596527241" };
		my $isbn = $class->new($trial_isbn, {normalizer => $normalizer});
		isa_ok $isbn, $class;
		return unless defined $isbn;
		ok $isbn->is_valid, 'ISBN is valid';
		};

	subtest 'extract from angle brackets' => sub {
		my $isbn = "<0596527241>";

		subtest 'fails otherwise' => sub {
			my $result = $class->new($isbn, {strict => 1});
			ok ! ref $result, "strict rejects ($isbn)";
			};

		subtest 'custom normalizer' => sub {
			my $normalizer = sub { $_[0] =~ /<(.*?)>/ ? $1 : () };
			my $isbn = $class->new( "<0596527241>", {normalizer => $normalizer});
			isa_ok $isbn, $class;
			return unless defined $isbn;
			ok $isbn->is_valid, 'ISBN is valid';
			};
		};
	};

done_testing();
