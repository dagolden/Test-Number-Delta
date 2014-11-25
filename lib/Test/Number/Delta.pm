use strict;
use warnings;

package Test::Number::Delta;
# ABSTRACT: Compare the difference between numbers against a given tolerance

our $VERSION = '1.06';

use vars qw (@EXPORT @ISA);

# Required modules
use Carp;
use Test::Builder;
use Exporter;

@ISA    = qw( Exporter );
@EXPORT = qw( delta_not_ok delta_ok delta_within delta_not_within );

=head1 SYNOPSIS

  # Import test functions
  use Test::Number::Delta;

  # Equality test with default tolerance
  delta_ok( 1e-5, 2e-5, 'values within 1e-6');

  # Inequality test with default tolerance
  delta_not_ok( 1e-5, 2e-5, 'values not within 1e-6');

  # Provide specific tolerance
  delta_within( 1e-3, 2e-3, 1e-4, 'values within 1e-4');
  delta_not_within( 1e-3, 2e-3, 1e-4, 'values not within 1e-4');

  # Compare arrays or matrices
  @a = ( 3.14, 1.41 );
  @b = ( 3.15, 1.41 );
  delta_ok( \@a, \@b, 'compare @a and @b' );

  # Set a different default tolerance
  use Test::Number::Delta within => 1e-5;
  delta_ok( 1.1e-5, 2e-5, 'values within 1e-5'); # ok

  # Set a relative tolerance
  use Test::Number::Delta relative => 1e-3;
  delta_ok( 1.01, 1.0099, 'values within 1.01e-3');


=head1 DESCRIPTION

At some point or another, most programmers find they need to compare
floating-point numbers for equality.  The typical idiom is to test
if the absolute value of the difference of the numbers is within a desired
tolerance, usually called epsilon.  This module provides such a function for use
with L<Test::More>.  Usage is similar to other test functions described in
L<Test::More>.  Semantically, the C<delta_within> function replaces this kind
of construct:

 ok ( abs($p - $q) < $epsilon, '$p is equal to $q' ) or
     diag "$p is not equal to $q to within $epsilon";

While there's nothing wrong with that construct, it's painful to type it
repeatedly in a test script.  This module does the same thing with a single
function call.  The C<delta_ok> function is similar, but either uses a global
default value for epsilon or else calculates a 'relative' epsilon on
the fly so that epsilon is scaled automatically to the size of the arguments to
C<delta_ok>.  Both functions are exported automatically.

Because checking floating-point equality is not always reliable, it is not
possible to check the 'equal to' boundary of 'less than or equal to
epsilon'.  Therefore, Test::Number::Delta only compares if the absolute value
of the difference is B<less than> epsilon (for equality tests) or
B<greater than> epsilon (for inequality tests).

=head1 USAGE

=head2 use Test::Number::Delta;

With no arguments, epsilon defaults to 1e-6. (An arbitrary choice on the
author's part.)

=head2 use Test::Number::Delta within => 1e-9;

To specify a different default value for epsilon, provide a C<within> parameter
when importing the module.  The value must be non-zero.

=head2 use Test::Number::Delta relative => 1e-3;

As an alternative to using a fixed value for epsilon, provide a C<relative>
parameter when importing the module.  This signals that C<delta_ok> should
test equality with an epsilon that is scaled to the size of the arguments.
Epsilon is calculated as the relative value times the absolute value
of the argument with the greatest magnitude.  Mathematically, for arguments
'x' and 'y':

 epsilon = relative * max( abs(x), abs(y) )

For example, a relative value of "0.01" would mean that the arguments are equal
if they differ by less than 1% of the larger of the two values.  A relative
value of 1e-6 means that the arguments must differ by less than 1 millionth
of the larger value.  The relative value must be non-zero.

=head2 Combining with a test plan

 use Test::Number::Delta 'no_plan';

 # or

 use Test::Number::Delta within => 1e-9, tests => 1;

If a test plan has not already been specified, the optional
parameter for Test::Number::Delta may be followed with a test plan (see
L<Test::More> for details).  If a parameter for Test::Number::Delta is
given, it must come first.

=cut

my $Test     = Test::Builder->new;
my $Epsilon  = 1e-6;
my $Relative = undef;

sub import {
    my $self  = shift;
    my $pack  = caller;
    my $found = grep /within|relative/, @_;
    croak "Can't specify more than one of 'within' or 'relative'"
      if $found > 1;
    if ($found) {
        my ( $param, $value ) = splice @_, 0, 2;
        croak "'$param' parameter must be non-zero"
          if $value == 0;
        if ( $param eq 'within' ) {
            $Epsilon = abs($value);
        }
        elsif ( $param eq 'relative' ) {
            $Relative = abs($value);
        }
        else {
            croak "Test::Number::Delta parameters must come first";
        }
    }
    $Test->exported_to($pack);
    $Test->plan(@_);
    $self->export_to_level( 1, $self, $_ ) for @EXPORT;
}

#--------------------------------------------------------------------------#
# _check -- recursive function to perform comparison
#--------------------------------------------------------------------------#

sub _check {
    my ( $p, $q, $e, $name, @indices ) = @_;
    my $epsilon;

    if ( !defined $e ) {
        $epsilon =
            $Relative
          ? $Relative * ( abs($p) > abs($q) ? abs($p) : abs($q) )
          : $Epsilon;
    }
    else {
        $epsilon = abs($e);
    }

    my ( $ok, $diag ) = ( 1, q{} ); # assume true
    if ( ref $p eq 'ARRAY' || ref $q eq 'ARRAY' ) {
        if ( @$p == @$q ) {
            for my $i ( 0 .. $#{$p} ) {
                my @new_indices;
                ( $ok, $diag, @new_indices ) =
                  _check( $p->[$i], $q->[$i], $e, $name, scalar @indices ? @indices : (), $i, );
                if ( not $ok ) {
                    @indices = @new_indices;
                    last;
                }
            }
        }
        else {
            $ok = 0;
            $diag =
                "Got an array of length "
              . scalar(@$p)
              . ", but expected an array of length "
              . scalar(@$q);
        }
    }
    else {
        $ok = $p == $q || abs( $p - $q ) < $epsilon;
        if ( !$ok ) {
            my ( $ep, $dp ) = _ep_dp($epsilon);
            $diag = sprintf( "%.${dp}f and %.${dp}f are not equal" . " to within %.${ep}f",
                $p, $q, $epsilon );
        }
    }
    return ( $ok, $diag, scalar(@indices) ? @indices : () );
}

sub _ep_dp {
    my $epsilon = shift;
    return ( 0, 0 ) unless $epsilon;
    $epsilon = abs($epsilon);
    my ($exp) = sprintf( "%e", $epsilon ) =~ m/e(.+)/;
    my $ep = $exp < 0 ? -$exp : 1;
    my $dp = $ep + 1;
    return ( $ep, $dp );
}

sub _diag_default {
    my ($ep) = _ep_dp( abs( $Relative || $Epsilon ) );
    my $diag = "Arguments are equal to within ";
    $diag .=
      $Relative
      ? sprintf( "relative tolerance %.${ep}f", abs($Relative) )
      : sprintf( "%.${ep}f",                    abs($Epsilon) );
    return $diag;
}

=head1 FUNCTIONS

=cut

#--------------------------------------------------------------------------#
# delta_within()
#--------------------------------------------------------------------------#

=head2 delta_within

 delta_within(  $p,  $q, $epsilon, '$p and $q are equal within $epsilon' );
 delta_within( \@p, \@q, $epsilon, '@p and @q are equal within $epsilon' );

This function tests for equality within a given value of epsilon. The test is
true if the absolute value of the difference between $p and $q is B<less than>
epsilon.  If the test is true, it prints an "OK" statement for use in testing.
If the test is not true, this function prints a failure report and diagnostic.
Epsilon must be non-zero.

The values to compare may be scalars or references to arrays.  If the values
are references to arrays, the comparison is done pairwise for each index value
of the array.  The pairwise comparison is recursive, so matrices may
be compared as well.

For example, this code sample compares two matrices:

    my @a = (   [ 3.14, 6.28 ],
                [ 1.41, 2.84 ]   );

    my @b = (   [ 3.14, 6.28 ],
                [ 1.42, 2.84 ]   );

    delta_within( \@a, \@b, 1e-6, 'compare @a and @b' );

The sample prints the following:

    not ok 1 - compare @a and @b
    # At [1][0]: 1.4100000 and 1.4200000 are not equal to within 0.000001

=cut

sub delta_within($$$;$) { ## no critic
    my ( $p, $q, $epsilon, $name ) = @_;
    croak "Value of epsilon to delta_within must be non-zero"
      if !defined($epsilon) || $epsilon == 0;
    {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        _delta_within( $p, $q, $epsilon, $name );
    }
}

sub _delta_within {
    my ( $p, $q, $epsilon, $name ) = @_;
    my ( $ok, $diag, @indices ) = _check( $p, $q, $epsilon, $name );
    if (@indices) {
        $diag = "At [" . join( "][", @indices ) . "]: $diag";
    }
    return $Test->ok( $ok, $name ) || $Test->diag($diag);
}

#--------------------------------------------------------------------------#
# delta_ok()
#--------------------------------------------------------------------------#

=head2 delta_ok

 delta_ok(  $p,  $q, '$p and $q are close enough to equal' );
 delta_ok( \@p, \@q, '@p and @q are close enough to equal' );

This function tests for equality within a default epsilon value.  See L</USAGE>
for details on changing the default.  Otherwise, this function works the same
as C<delta_within>.

=cut

sub delta_ok($$;$) { ## no critic
    my ( $p, $q, $name ) = @_;
    {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        _delta_within( $p, $q, undef, $name );
    }
}

#--------------------------------------------------------------------------#
# delta_not_ok()
#--------------------------------------------------------------------------#

=head2 delta_not_within

 delta_not_within(  $p,  $q, '$p and $q are different' );
 delta_not_within( \@p, \@q, $epsilon, '@p and @q are different' );

This test compares inequality in excess of a given value of epsilon. The test
is true if the absolute value of the difference between $p and $q is B<greater
than> epsilon.  For array or matrix comparisons, the test is true if I<any>
pair of values differs by more than epsilon.  Otherwise, this function works
the same as C<delta_within>.

=cut

sub delta_not_within($$$;$) { ## no critic
    my ( $p, $q, $epsilon, $name ) = @_;
    croak "Value of epsilon to delta_not_within must be non-zero"
      if !defined($epsilon) || $epsilon == 0;
    {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        _delta_not_within( $p, $q, $epsilon, $name );
    }
}

sub _delta_not_within($$$;$) { ## no critic
    my ( $p, $q, $epsilon, $name ) = @_;
    my ( $ok, undef, @indices ) = _check( $p, $q, $epsilon, $name );
    $ok = !$ok;
    my ( $ep, $dp ) = _ep_dp($epsilon);
    my $diag =
      defined($epsilon)
      ? sprintf( "Arguments are equal to within %.${ep}f", abs($epsilon) )
      : _diag_default();
    return $Test->ok( $ok, $name ) || $Test->diag($diag);
}

=head2 delta_not_ok

 delta_not_ok(  $p,  $q, '$p and $q are different' );
 delta_not_ok( \@p, \@q, '@p and @q are different' );

This function tests for inequality in excess of a default epsilon value.  See
L</USAGE> for details on changing the default.  Otherwise, this function works
the same as C<delta_not_within>.

=cut

sub delta_not_ok($$;$) { ## no critic
    my ( $p, $q, $name ) = @_;
    {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        _delta_not_within( $p, $q, undef, $name );
    }
}

=head1 SEE ALSO

=for :list
* L<Number::Tolerant>
* L<Test::Deep::NumberTolerant>

=cut

1;
