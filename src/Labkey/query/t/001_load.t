# -*- perl -*-

# t/001_load.t - check module loading and create testing directory

use Test::More tests => 2;

BEGIN { use_ok( 'Labkey::query' ); }

ok (Labkey::query->can('selectRows'));

