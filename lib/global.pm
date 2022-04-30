#!/usr/bin/perl

package global;

use strict;
use warnings;
use v5.14;
no autovivification;
use Data::Printer;
use JSON;
use DBI;
use Hash::Merge;
use Exporter; # Gain export capabilities 
use FindBin;
use lib "$FindBin::Bin/../lib";
use config;


# Exported variables & functions.
our (@EXPORT, @ISA);    # Global variables 
our $databaseName        = $config{'databaseName'} // die;
our $softwareEnvironment = $config{'environment'}  // die;
our $dbh                 = connect_dbi();

@ISA    = qw(Exporter); # Take advantage of Exporter's capabilities
@EXPORT = qw(
	$databaseName
	$softwareEnvironment
	$dbh
);                      # Exported variables.

sub connect_dbi {
    die unless -f $configFile;
    my $config = do("./$configFile");
    return DBI->connect("DBI:mysql:database=" . $databaseName . ";" .
                        "host=" . $config->{'databaseHost'} . ";port=" . $config->{'databasePort'},
                        $config->{'databaseUser'}, $config->{'databasePassword'},
                        { PrintError => 1, mysql_enable_utf8 => 1}) || die $DBI::errstr;
}

1;