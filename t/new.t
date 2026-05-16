use strict;
use warnings;

use Test::More;

my $class   = 'Business::ISBN';
my @methods = qw(new);

subtest 'sanity' => sub {
	use_ok $class,;
	can_ok $class, @methods;
	};

subtest 'new' => sub {
	my @table = (
		# input,                                                            success, return, is_valid, error code, error text, label
		[ [                                                           ],    0,       undef,  0,        undef,      qr//,       'no args'                        ],
		[ [                                             {}            ],    0,       undef,  0,        undef,      qr//,       'empty hashref'                  ],
		[ [                                             {strict => 1} ],    0,       undef,  0,        undef,      qr//,       'empty hashref'                  ],

		[ [q(abc)                                                     ],    0,       undef,  0,        undef,      qr//,       'no good chars'                  ],
		[ [q(abc),                                      {}            ],    0,       undef,  0,        undef,      qr//,       'no good chars, empty hashref'   ],
		[ [q(abc),                                      {strict => 1} ],    0,       undef,  0,        undef,      qr//,       'no good chars, strict'          ],

		[ [q(000)],                                                         0,       undef,  0,        undef,      qr//,       'not enough chars'               ],
		[ [q(000),                                      {}            ],    0,       undef,  0,        undef,      qr//,       'not enough chars empty hashref' ],
		[ [q(000),                                      {strict => 1} ],    0,       undef,  0,        undef,      qr//,       'not enough chars, strict'       ],

		[ [q(0b2c3d4e5f6g7h8i9kX)],                                         1,       undef,  0,        undef,      qr//,       'accidental ISBN'                ],
		[ [q(0b2c3d4e5f6g7h8i9kX),                      {}            ],    1,       undef,  0,        undef,      qr//,       'accidental ISBN empty hashref'  ],
		[ [q(0b2c3d4e5f6g7h8i9kX),                      {strict => 1} ],    0,       undef,  0,        undef,      qr//,       'accidental ISBN, strict'        ],

		[ [q(13456789X)],                                                   0,       undef,  0,        undef,      qr//,       'not enough chars'               ],
		[ [q(13456789X),                                {}            ],    0,       undef,  0,        undef,      qr//,       'not enough chars empty hashref' ],
		[ [q(13456789X),                                {strict => 1} ],    0,       undef,  0,        undef,      qr//,       'not enough chars, strict'       ],

		[ [q(0b2c3d4e5f6g7h8i9kX)                                     ],    1,       undef,  0,        undef,      qr//,       'accidental ISBN, strict'        ],
		[ [q(0b2c3d4e5f6g7h8i9kX),                      {strict => 1} ],    0,       undef,  0,        undef,      qr//,       'accidental ISBN, strict'        ],

		[ [q(  0 2345 6789X  )                                        ],    1,       undef,  0,        undef,      qr//,       'whitespace, legacy'             ],
		[ [q(  0 2345 6789X  ),                         {strict => 1} ],    1,       undef,  0,        undef,      qr//,       'whitespace, strict'             ],
		[ [qq(  0-2\x{2011}34\x{2212}5\x{2014}6789X  )                ],    1,       undef,  0,        undef,      qr//,       'whitespace, dashes, legacy'     ],
		[ [qq(  0-2\x{2011}34\x{2212}5\x{2014}6789X  ), {strict => 1} ],    1,       undef,  0,        undef,      qr//,       'whitespace, dashes, strict'     ],
		[ [qq(  A-2\x{2011}34\x{2212}5\x{2014}6789X  ), {strict => 1} ],    0,       undef,  0,        undef,      qr//,       'disallowed, whitespace, dashes, strict'     ],
		);

	foreach my $row ( @table ) {
		my( $input, $success, $return, $is_valid, $error_code, $error_text, $label) = @$row;
		subtest $label => sub {
			my $isbn = $class->new(@$input);
			if( $success ) {
				isa_ok $isbn, $class;
				can_ok $isbn, qw(is_valid) or return;
				is !! $isbn->is_valid, !! $is_valid, 'matches expected validity';
				diag $isbn->error_text;
				}
			else {
				is $isbn, $return, 'bad argument returns undef';
				}
			};
		}
	};


done_testing();
