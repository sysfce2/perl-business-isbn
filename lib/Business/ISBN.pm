use 5.008;

package Business::ISBN;
use strict;

=encoding utf8

=head1 NAME

Business::ISBN - work with International Standard Book Numbers

=head1 SYNOPSIS

	use Business::ISBN;

	# 10 digit ISBNs
	$isbn10 = Business::ISBN->new('1565922573');
	$isbn10 = Business::ISBN->new('1-56592-257-3');

	# 13 digit ISBNs
	$isbn13 = Business::ISBN->new('978-0-596-52724-2');

	# convert
	$isbn10 = $isbn13->as_isbn10;    # for the 978 prefixes

	$isbn13 = $isbn10->as_isbn13;

	# maybe you don't care what it is as long as everything works
	$isbn = Business::ISBN->new( $ARGV[0] );

	#print the ISBN with hyphens at usual positions
	print $isbn->as_string;

	#print the ISBN with hyphens at specified positions.
	#this not does affect the default positions
	print $isbn->as_string([]);

	#print the group code or publisher code
	print $isbn->group_code;

	print $isbn->publisher_code;

	#check to see if the ISBN is valid
	$isbn->is_valid;

	#fix the ISBN checksum.  BEWARE:  the error might not be
	#in the checksum!
	$isbn->fix_checksum;

	# create an EAN13 barcode in PNG format
	$isbn->png_barcode;

=head1 DESCRIPTION

This modules handles International Standard Book Numbers, including
ISBN-10 and ISBN-13.

The data come from L<Business::ISBN::Data>, which means you can update
the data separately from the code. Also, you can use L<Business::ISBN::Data>
with whatever F<RangeMessage.xml> you like if you have updated data. See
that module for details.

=cut

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # Boring set up stuff
use subs qw(
	_common_format
	INVALID_GROUP_CODE
	INVALID_PUBLISHER_CODE
	BAD_CHECKSUM
	GOOD_ISBN
	BAD_ISBN
	ARTICLE_CODE_OUT_OF_RANGE
	);
use vars qw(
	@EXPORT_OK
	%EXPORT_TAGS
	%group_data
	$MAX_GROUP_CODE_LENGTH
	);

use Carp qw(carp croak cluck);
use Exporter qw(import);

use Business::ISBN::Data 20230322.001; # now a separate module
# ugh, hack
*group_data = *Business::ISBN::country_data;
sub _group_data {
  my $isbn_prefix
    = ref $_[0] eq 'Business::ISBN13'
    ? $_[0]->prefix
    : "978";
  return $group_data{ $isbn_prefix }->{ $_[1] };
}

sub _max_group_code_length  { $Business::ISBN::MAX_COUNTRY_CODE_LENGTH };
sub _max_publisher_code_length  {
	  $_[0]->_max_length

	- $_[0]->_prefix_length     # prefix

	- $_[0]->_group_code_length # group
	- 1                         # article
	- 1;                        # checksum
	};

sub _publisher_ranges {
	my $self = shift;
	[ @{ $self->_group_data( $self->group_code )->[1] } ];
	}

my $debug = $ENV{BUSINESS_ISBN_DEBUG};

BEGIN {
	@EXPORT_OK = qw(
		INVALID_GROUP_CODE INVALID_PUBLISHER_CODE
		BAD_CHECKSUM GOOD_ISBN BAD_ISBN ARTICLE_CODE_OUT_OF_RANGE
		INVALID_PREFIX
		%ERROR_TEXT
		normalize_isbn_string
		valid_isbn_checksum
		);

	%EXPORT_TAGS = (
		'all' => \@EXPORT_OK,
		);
	};

our $VERSION   = '3.014';

sub ARTICLE_CODE_OUT_OF_RANGE () { -5 }
sub INVALID_PREFIX            () { -4 };
sub INVALID_GROUP_CODE        () { -2 };
sub INVALID_PUBLISHER_CODE    () { -3 };
sub BAD_CHECKSUM              () { -1 };
sub GOOD_ISBN                 () {  1 };
sub BAD_ISBN                  () {  0 };

our %ERROR_TEXT = (
	 0 => "Bad ISBN",
	 1 => "Good ISBN",
	-1 => "Bad ISBN checksum",
	-2 => "Invalid group code",
	-3 => "Invalid publisher code",
	-4 => "Invalid prefix (must be 978 or 979)",
	-5 => "Incremented article code would be out of range",
	);

use Business::ISBN10;
use Business::ISBN13;

=head2 Function interface

=over 4

=item normalize_isbn_string( STRING )

This differs from the module default transformation which removes all
characters that can't be part of a valid ISBN. This does a targeted
transformation that removes fewer types of characters to a string such as
C<123456789ABC...XYZ> doesn't accidentally look like the ISBN
C<123456789X>.

The C<normalize_isbn_string> function is much more targeted. It strips out
the characters that might be there accidentally from a data import or
export problem (the main reason this module was created). This include
horizontal whitespace within the string, vertical whitespace around the
string, and various forms of dashes (e.g. from too-helpful word
processors).

=over 4

=item 1. remove all horizontal space

=item 2. remove vertical whitespace from the beginning and end of the string

=item 3. remove dash (U+002D) and dash-type characters (U+2010 to U+2015, and U+2212)

=back

If the result looks like the format of an ISBN-10 or ISBN-13, it returns
the string. Otherwise, it returns the empty list.

You could use this as a filter to catch bad input since C<new> is too forgiving:

	use Business::ISBN qw(normalize_isbn_string);

	while( my $candidate = <> ) {
		next unless $candidate = normlize_isbn_string($candidate);
		my $isbn = Business::ISBN->new($candidate);
		...
		}

But, 3.016 will do this for you with with the C<strict> option:

	my $isbn = Business::ISBN->new( $candidate, { strict => 1 } );

=cut

sub normalize_isbn_string {
	my($string) = @_;

	$string =~ s/   [\t\x{180E}\p{Space_Separator}]        //xg;
	$string =~ s/\A [\x0A-\x0D\x{0085}\x{2028}\x{2029}]+   //x;
	$string =~ s/   [\x0A-\x0D\x{0085}\x{2028}\x{2029}]+ \z//x;

	$string =~ s/[\x{2010}-\x{2015}\x{2212}-]//g;
	$string = uc($string);

	return $string;
	}

=item valid_isbn_checksum( ISBN10 | ISBN13 )

This function is exportable on demand, and works for either 10
or 13 character ISBNs).

	use Business::ISBN qw( valid_isbn_checksum );

Returns 1 if the ISBN is a valid ISBN with the right checksum.

Returns 0 if the ISBN has valid prefix and publisher codes, but an
invalid checksum.

Returns undef if the ISBN does not validate for any other reason.

=back

=cut

sub valid_isbn_checksum {
	my $isbn = shift;

	my $obj =  Business::ISBN->new( $isbn );
	return unless defined $obj;

	return 1 if $obj->is_valid_checksum == GOOD_ISBN;
	return 0 if $obj->is_valid_checksum == BAD_CHECKSUM;
	return;
	}

=head2 Object interface

=over 4

=item new($isbn)

The constructor accepts a scalar representing the ISBN, and an optional
options hash reference (new in 3.016).

Prior to 3.016, C<new> would fix up it argument by removing anything that
wasn't an ASCII digit or an C<X> (see C<_common_format>). However, that can
accidentally make a string that isn't an ISBN into one after all the other
characters are removed (e.g. C<123456789ABCD...XYZ>).

	use Business::ISBN;

	my $isbn = Business::ISBN->new($input_string);
	unless( defined $isbn ) {
		... handle error ...
		}

With 3.016, C<new> can take an optional hash reference as a second
argument. Set the hash key C<strict> to true to use a more restrictive way
to prepare the string. The stricter method uses C<normalize_isbn_string>,
which only strips whitespace and dashes. Any extra letters will remain,
causing C<new> to fail:

	use Business::ISBN 3.016;
	my $isbn = Business::ISBN->new($input_string, { strict => 1 });
	unless( defined $isbn ) {
		... handle error ...
		}

If that's not good enough for you, 3.016 also lets you use your own code
reference to decide how to handle the string-to-ISBN conversion. Use the
C<normalizer> option to fix-up the ISBN argument based on your source. The
code ref should return the string that the parser should use:

	use Business::ISBN 3.016;

	my $code_ref = sub {
		my $input = shift;
		my $candidate = ...;
		return $candidate;
		};

	my $isbn = Business::ISBN->new($input_string, { normalizer => $code_ref });
	unless( defined $isbn ) {
		... handle error ...
		}

For example, if you get ISBN strings like C<< <123456789X> >>, you can do
something like this:

	my $code_ref = sub { $_[0] =~ m/<(.*?)>/ ? $1 : () };

No matter which method you choose (legacy, strict, or custom), the result,
in the case of a valid ISBN, should match C<(?:[0-9]{3})?[0-9]{9}[0-9X]>.
If the string does not match, C<new> returns the empty list immediately.

The parsing uses L<Business::ISBN::Data> to determine the group code and
the publisher code. If these data cannot be determined, it sets C<<
$obj->error >> to something other than C<GOOD_ISBN>. An object is still
returned and it is up to the program to check the C<< error >> method for
one of five values or one of the C<< error_* >> methods to check for a
particular error. The actual values of these symbolic versions are the same
as those from previous versions of this module which used literal values:


	Business::ISBN::INVALID_PUBLISHER_CODE
	Business::ISBN::INVALID_GROUP_CODE
	Business::ISBN::BAD_CHECKSUM
	Business::ISBN::GOOD_ISBN
	Business::ISBN::BAD_ISBN

If you have one of these values and want to turn it into a string, you
can use the C<%Business::ISBN::ERROR_TEXT> hash, which is exportable
by asking for it explicitly in the import list:

	use Business::ISBN qw(%ERROR_TEXT);

As of version 2.010_01, you can get this text from C<< error_text >>
so you don't have to import anything or look in package variables.

The string passed as the ISBN need not be valid as long as it superficially
looks like one.  This allows one to use the C<fix_checksum()> method.
Despite the disclaimer in the discussion of that method, the author has
found it extremely useful.  One should check the validity of the ISBN with
C<is_valid()> rather than relying on the return value of the constructor.
If all one wants to do is check the validity of an ISBN, one can skip the
object-oriented interface and use the C<valid_isbn_checksum()> function
which is exportable on demand.

If the constructor decides it cannot create an object, it returns C<undef>.
It may do this if the string passed as the ISBN cannot be munged to the
internal format, meaning that it does not even come close to looking like
an ISBN.

=cut

sub new {
	my( $class, $input_data, $opts ) = @_;

	# since this adds a new feature to code that has existed for
	# decades, I want this to ignore goofy situations that might
	# be out there. new() never used the third argument, but didn't
	# forbid it either.
	$opts = {} unless defined $opts;
	$opts->{'strict'} = 0 unless defined $opts->{'strict'};

	unless( defined $opts->{'normalizer'} and ref $opts->{'normalizer'} eq ref sub {} ) {
		my $method_name = $opts->{'strict'} ? 'normalize_isbn_string' : '_common_format';
		$opts->{'normalizer'} = $class->can($method_name);
		}

	my $common_data = $opts->{'normalizer'}->($input_data);
	$common_data = '' unless defined $common_data;

	return unless $common_data =~ /\A ([0-9]{3})? [0-9]{9} [0-9X] \z/x;

	my $self = {
		input_isbn  => $input_data,
		common_data => $common_data
		};

	my $isbn = do {
		if( length( $common_data ) == 10 ) {
			bless $self, 'Business::ISBN10';
			}
		elsif( length( $common_data ) == 13 ) {
			bless $self, 'Business::ISBN13';
			}
		else {
			return BAD_ISBN;
			}
		};

	$self->_init( $common_data );
	$self->_parse_isbn( $common_data );

	return $isbn;
	}

=back

=head2 Instance methods

=over 4

=item input_isbn

Returns the starting ISBN. Since you may insert hyphens or fix
checksums, you might want to see the original data.

=cut

sub input_isbn { $_[0]->{'input_isbn'} }

=item common_data

Returns the starting ISBN after normalization, which removes anything
that isn't a digit or a valid checksum character.

=cut

sub common_data { $_[0]->{'common_data'} }


=item isbn

Returns the current value of ISBN, even if it has an invalid checksum.
This is the raw data so it doesn't have the hyphens. If you want
hyphenation, try C<as_string>.

The C<isbn> method should be the same as C<as_string( [] )>.

=cut

sub isbn { $_[0]->{'isbn'} }

=item error

Return the error code for the reason the ISBN isn't valid. The return
value is a key in %ERROR_TEXT.

=cut

sub error { $_[0]->{'valid'} < 1 and $_[0]->{'valid'} }

=item error_is_bad_group

=item error_is_bad_publisher

=item error_is_article_out_of_range

=item error_is_bad_checksum

Returns true if the ISBN error is that type.

=cut

sub error_is_bad_group {
	return $_[0]->error == INVALID_GROUP_CODE;
	}

sub error_is_bad_publisher {
	return $_[0]->error == INVALID_PUBLISHER_CODE;
	}

sub error_is_article_out_of_range {
	return $_[0]->error == ARTICLE_CODE_OUT_OF_RANGE;
	}

sub error_is_bad_checksum {
	return $_[0]->error == BAD_CHECKSUM;
	}

=item error_text

Returns a text version of the error text

=cut

sub error_text { $ERROR_TEXT{$_[0]->{'valid'}} }

=item is_valid

Return true if the ISBN is valid, meaning that it has a valid prefix
(for ISBN-13), group code, and publisher code; and its checksum
validates.

=cut

sub is_valid { $_[0]->{'valid'} eq GOOD_ISBN }

=item type

Returns either C<ISBN10> or C<ISBN13>.

=cut

sub type { $_[0]->{'type'} }


=item prefix

Returns the prefix for the ISBN. This is currently either 978 or 979
for ISBN-13. It returns the empty string (so, a defined value) for
ISBN-10.

=cut

sub prefix         { $_[0]->{'prefix'} }
sub _prefix_length { length $_[0]->{'prefix'} }

=item group_code

Returns the group code for the ISBN. This is the numerical version,
for example, '0' for the English group. The valid group codes come
from C<Business::ISBN::Data>.

=cut

sub group_code { $_[0]->{'group_code'} }

=item group

Returns the group name for the ISBN. This is the string version. For
instance, 'English' for the '0' group. The names come from
C<Business::ISBN::Data>.

=cut

sub group { $_[0]->_group_data( $_[0]->group_code )->[0] }

sub _group_code_length {
	length(
		defined $_[0]->{'group_code'} ? $_[0]->{'group_code'} : ''
		);
	}

=item publisher_code

Returns the publisher code for the ISBN. This is the numeric version,
for instance '596' for O'Reilly Media.

=cut

sub publisher_code { $_[0]->{'publisher_code'} }
sub _publisher_code_length {
	length(
		defined $_[0]->{'publisher_code'} ? $_[0]->{'publisher_code'} : ''
		);
	}

=item article_code

Returns the article code for the ISBN. This is the numeric version that
uniquely identifies the item.

=cut

sub article_code { $_[0]->{'article_code'} }

=item article_code_length

Returns the article code length for the ISBN.

=cut

sub article_code_length { length $_[0]->{'article_code'} }

=item article_code_min

Returns the minimum article code length for the publisher code.

=cut

sub article_code_min { 0 }

=item article_code_max

Returns the max article code length for the publisher code.

=cut

sub article_code_max { '9' x $_[0]->article_code_length }

=item checksum

Returns the checksum code for the ISBN. This checksum may not be valid since
you can create an object an fix the checksum later with C<fix_checksum>.

=cut

sub checksum { $_[0]->{'checksum'} }
sub _checksum_pos { length( $_[0]->isbn ) - 1 }


=item is_valid_checksum

Returns C<Business::ISBN::GOOD_ISBN> for valid checksums and
C<Business::ISBN::BAD_CHECKSUM> otherwise. This does not guarantee
that the rest of the ISBN is actually assigned to a book.

=cut

sub is_valid_checksum {
	my $self = shift;

	cluck "is_valid_checksum: Didn't get object!" unless ref $self;

	no warnings 'uninitialized';
	return GOOD_ISBN if $self->checksum eq $self->_checksum;

	return BAD_CHECKSUM;
	}

=item fix_checksum

Checks the checksum and modifies the ISBN to set it correctly if needed.

=cut

sub fix_checksum {
	my $self = shift;

	my $last_char = substr($self->isbn, $self->_checksum_pos, 1);
	my $checksum = $self->_checksum;

	my $isbn = $self->isbn;
	substr($isbn, $self->_checksum_pos, 1) = $checksum;

	$self->_set_isbn( $isbn );
	$self->_set_checksum( $checksum );

	$self->_check_validity;

	return 0 if $last_char eq $checksum;
	return 1;
	}


=item as_string(), as_string([])

Return the ISBN as a string.  This function takes an
optional anonymous array (or array reference) that specifies
the placement of hyphens in the string.  An empty anonymous array
produces a string with no hyphens. An empty argument list
automatically hyphenates the ISBN based on the discovered
group and publisher codes.  An ISBN that is not valid may
produce strange results.

The positions specified in the passed anonymous array
are only used for one method use and do not replace
the values specified by the constructor. The method
assumes that you know what you are doing and will attempt
to use the least three positions specified.  If you pass
an anonymous array of several positions, the list will
be sorted and the lowest three positions will be used.
Positions less than 1 and greater than 12 are silently
ignored.

A terminating 'x' is changed to 'X'.

=cut

sub as_string {
	my $self      = shift;
	my $array_ref = shift;

	#this allows one to override the positions settings from the
	#constructor
	$array_ref = $self->_hyphen_positions unless ref $array_ref eq ref [];

#	print STDERR Data::Dumper->Dump( [$array_ref], [qw(array_ref)] );
#	print STDERR Data::Dumper->Dump( [$self], [qw(self)] );

	return unless $self->is_valid eq GOOD_ISBN;
	my $isbn = $self->isbn;

	foreach my $position ( sort { $b <=> $a } @$array_ref ) {
		next if $position > 12 or $position < 1;
		substr($isbn, $position, 0) = '-';
		}

	return $isbn;
	}

=item as_isbn10

Returns a new ISBN object. If the object is already ISBN-10, this method
clones it. If it is an ISBN-13 with the prefix 978, it returns the ISBN-10
equivalent. For all other cases it returns undef.

=cut

sub as_isbn10 {
	croak "as_isbn10() must be implemented in Business::ISBN subclass"
	}

=item as_isbn13

Returns a new ISBN object. If the object is already ISBN-13, this method
clones it. If it is an ISBN-10, it returns the ISBN-13 equivalent with the
978 prefix.

=cut

sub as_isbn13 {
	croak "as_isbn13() must be implemented in Business::ISBN subclass"
	}

=item increment

Returns the next C<Business::ISBN> by incrementing the article code of
the specified ISBN (object or scalar).

Returns undef, if the parameter is invalid or equals the maximum
possible ISBN for the publisher.

	$isbn = Business::ISBN->new('1565922573');  # 1-56592-257-3
	$next_isbn = $isbn->increment;              # 1-56592-258-1

If the next article code would exceed the maximum possible article
code (such as incrementing 999 to 1000), this returns ARTICLE_CODE_OUT_OF_RANGE
as the error.

=cut

sub increment { $_[0]->_step_article_code( +1 ) }

=item decrement

Returns the previous C<Business::ISBN> by decrementing the article
code of the specified ISBN (object or scalar).

Returns undef, if the parameter is invalid or equals the minimum
possible ISBN for the publisher.

	$isbn = Business::ISBN->new('1565922573');  # 1-56592-257-3
	$prev_isbn = $isbn->decrement;              # 1-56592-256-5

If the next article code would exceed the maximum possible article
code (such as incrementing 000 to -1), this returns ARTICLE_CODE_OUT_OF_RANGE
as the error.

=cut

sub decrement { $_[0]->_step_article_code( -1 ) }

sub _step_article_code {
	my( $self, $step ) = @_;
	carp "The step for _step_isbn must be an integer"
		unless( $step == int $step and $step != 0 );

	my $next_article_code = int $self->article_code + $step;

	return ARTICLE_CODE_OUT_OF_RANGE unless
		$next_article_code >= $self->article_code_min
			&&
		$next_article_code <= $self->article_code_max
		;

	my $next_isbn = Business::ISBN->new(
		join('',
			$self->prefix,
			$self->group_code,
			$self->publisher_code,
			sprintf( "%0*d", $self->article_code_length, $next_article_code ),
			'0'
			)
		);

	$next_isbn->fix_checksum;

	$next_isbn;
	}

=item png_barcode

Returns image data in PNG format for the barcode for the ISBN. This
works with ISBN-10 and ISBN-13. The ISBN-10s are automatically converted
to ISBN-13.

This requires C<GD::Barcode::EAN13>.

=cut

sub png_barcode {
	my $self = shift;

	my $ean = $self->as_isbn13->as_string([]);

	eval { require GD::Barcode::EAN13 };
	if( $@ ) {
		carp "Need GD::Barcode::EAN13 to use png_barcode!";
		return;
		}

	my $gd_image = GD::Barcode::EAN13->new($ean)->plot;
	my $image;
	if( $gd_image->can('png') ) {
		$image = GD::Barcode::EAN13->new($ean)->plot->png;
		}
	else {
		carp "Your GD module does not have PNG support";
		return;
		}

	return $image;
	}

=back

=cut

sub _set_isbn           {   $_[0]->{'isbn'}           = $_[1];   }

sub _set_is_valid       {   $_[0]->{'valid'}          = $_[1];   }

sub _set_prefix
	{
	croak "_set_prefix() must be implemented in Business::ISBN subclass"
	}

sub _set_group_code     {   $_[0]->{'group_code'}     = $_[1];   }

sub _set_group_code_string     {   $_[0]->{'group_code_string'}     = $_[1];   }

sub _set_publisher_code {   $_[0]->{'publisher_code'} = $_[1];   }

sub _set_publisher_code_string {   $_[0]->{'publisher_code_string'} = $_[1];   }

sub _set_article_code   {   $_[0]->{'article_code'}   = $_[1];   }

sub _set_checksum       {   $_[0]->{'checksum'}       = $_[1];   }

sub _set_type {
	croak "_set_type() must be implemented in Business::ISBN subclass"
	}


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # internal methods.  you don't get to use this one.
sub _common_format {
	no warnings qw(uninitialized);
	my $data = uc shift; # we want uppercase X's
	$data =~ s/[^0-9X]//g;
	return $data;
	}

sub _init {
	my $self = shift;
	my $common_data = shift;

	my $class = ref $self =~ m/.*::(.*)/g;

	$self->_set_type;
	$self->_set_isbn( $common_data );

	# we don't know if we have a valid group code yet
	# so let's assume that we don't
	$self->_set_is_valid( INVALID_GROUP_CODE );
	}

{
my @methods = (
	[ qw( prefix         ), INVALID_PREFIX         ],
	[ qw( group_code     ), INVALID_GROUP_CODE     ],
	[ qw( publisher_code ), INVALID_PUBLISHER_CODE ],
	[ qw( article_code   ), BAD_ISBN               ],
	[ qw( checksum       ), BAD_CHECKSUM           ],
	);

sub _parse_isbn {
	my $self = shift;

	foreach my $pair ( @methods ) {
		my( $method, $error_code ) = @$pair;

		my $parser = "_parse_$method";
		my $result = $self->$parser;

		unless( defined $result ) {
			$self->_set_is_valid( $error_code );
			#print STDERR "Got bad result for $method [$$self{isbn}]\n";
			return;
			}

		$method = "_set_$method";
		$self->$method( $result );
		}

	$self->_set_is_valid( $self->is_valid_checksum );

	return $self;
	}
}

sub _parse_group_code {
	my $self = shift;

	my $trial;  # try this to see what we get
	my $group_code_length = 0;

	my $count = 1;

	GROUP_CODE:
	while( defined( $trial= substr($self->isbn, $self->_prefix_length, $count++) ) ) {
		if( defined $self->_group_data( $trial ) ) {
			return $trial;
			last GROUP_CODE;
			}

		# if we've past the point of finding a group
		# code we're pretty much stuffed.
		return if $count > $self->_max_group_code_length;
		}

	return; #failed if I got this far
	}

sub _parse_publisher_code {
	my $self = shift;

	my $pairs = $self->_publisher_ranges;

	# get the longest possible publisher code
	# I'll try substrs of this to get the real one
	my $longest = substr(
		$self->isbn,
		$self->_prefix_length + $self->_group_code_length,
		$self->_max_publisher_code_length,
		);

	#print STDERR "Trying to parse publisher: longest [$longest]\n";
	while( @$pairs ) {
		my $lower  = shift @$pairs;
		my $upper  = shift @$pairs;

		my $trial  = substr( $longest, 0, length $lower );
		#print STDERR "Trying [$trial] with $lower <-> $upper [$$self{isbn}]\n";

		# this has to be a sring comparison because there are
		# possibly leading 0s
		if( $trial ge $lower and $trial le $upper )
			{
			#print STDERR "Returning $trial\n";
			return $trial;
			}

		}

	return; #failed if I got this far
	}

sub _parse_article_code {
	my $self = shift;

	my $head = $self->_prefix_length +
		$self->_group_code_length +
		$self->_publisher_code_length;
	my $length = length( $self->isbn ) - $head - 1;

	substr( $self->isbn, $head, $length );
	}

sub _parse_checksum {
	my $self = shift;

	substr( $self->isbn, -1, 1 );
	}

sub _check_validity {
	my $self = shift;

	if( $self->is_valid_checksum  eq GOOD_ISBN and
		defined $self->group_code and
		defined $self->publisher_code and
		defined $self->prefix
		) {
	    $self->_set_is_valid( GOOD_ISBN );
	    return GOOD_ISBN;
	    }
	else {
		$self->_set_is_valid( INVALID_PUBLISHER_CODE )
			unless defined $self->publisher_code;
		$self->_set_is_valid( INVALID_GROUP_CODE )
			unless defined $self->group_code;
		$self->_set_is_valid( INVALID_PREFIX )
			 unless defined $self->prefix;
		return;
		}
	}

sub _hyphen_positions {
	croak "hyphen_positions() must be implemented in Business::ISBN subclass"
	}


1;

__END__

=head1 BUGS


=head1 TO DO

* i would like to create the bar codes with the price extension

=head1 SOURCE AVAILABILITY

This source is in Github:

    https://github.com/briandfoy/business-isbn

=head1 AUTHOR

brian d foy C<< <briandfoy@pobox.com> >>

=head1 COPYRIGHT AND LICENSE

Copyright © 2001-2026, brian d foy <briandfoy@pobox.com>. All rights reserved.

This module is licensed under the Artistic License 2.0. See the LICENSE
file in the distribution, or https://opensource.org/licenses/Artistic-2.0

=head1 CREDITS

Thanks to Mark W. Eichin C<< <eichin@thok.org> >> for suggestions and
discussions on EAN support.

Thanks to Andy Lester C<< <andy@petdance.com> >> for lots of bug fixes
and testing.

Ed Summers C<< <esummers@cpan.org> >> has volunteered to help with
this module.

Markus Spann C<< <markus_spann@gmx.de> >> added C<increment> and C<decrement>.

=cut
