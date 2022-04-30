#!/usr/bin/perl

package config;

use strict;
use warnings;
use v5.14;
no autovivification;
use Data::Printer;
use JSON;
use DBI;
use Hash::Merge;
use Exporter; # Gain export capabilities 

our $configFile = "open_vaet.conf";
our %config     = load_config();
our %enums      = load_enums();

# Exported variables & functions.
our (@EXPORT, @ISA);    # Global variables 

@ISA    = qw(Exporter); # Take advantage of Exporter's capabilities
@EXPORT = qw(
    $configFile
    %config
    %enums
);                      # Exported variables.

sub load_config {
    unless (-f $configFile) {
        $configFile = "../../open_vaet.conf";
        die unless -f $configFile;
    }
    my $config = do("./$configFile");
    return %$config;
}

sub load_enums {
    my $file = 'config/enums.json';
    unless (-f $file) {
        $file = '../../config/enums.json';
        die unless -f $file;
    }
    my $json;
    {
        local $/;
        open my $fh, "<:utf8", $file;
        $json = <$fh>;
        close $fh;
    }
    my $enums = JSON->new->utf8(0)->decode($json);
    return %$enums;
}

1;