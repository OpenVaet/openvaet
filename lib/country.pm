#!/usr/bin/perl

package country;

use strict;
use warnings;
use v5.14;
use JSON;
use DBI;
use Hash::Merge;
use Exporter; # Gain export capabilities 

# Exported variables & functions.
our (@EXPORT, @ISA);    # Global variables 

@ISA    = qw(Exporter); # Take advantage of Exporter's capabilities
@EXPORT = qw(

);                      # Exported variables.

sub country_id_from_name {
    my ($dbh, $countryName) = @_;
    my $tb = $dbh->selectrow_hashref("SELECT id as countryId FROM country WHERE name = ?", undef, $countryName);
    die unless keys %$tb;
    return %$tb{'countryId'};
}

1;