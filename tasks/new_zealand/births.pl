#!/usr/bin/perl
use strict;
use warnings;
use Statistics::Descriptive;

my %data = (
    2010 => 63897, 2011 => 61404, 2012 => 61179, 2013 => 58719, 2014 => 57243,
    2015 => 61038, 2016 => 59430, 2017 => 59610, 2018 => 58020, 2019 => 59637,
    2020 => 57573, 2021 => 58659, 2022 => 58887
);

my @decade = @data{2010..2019};
my @recent_years = @data{2020..2022};

my $stat = Statistics::Descriptive::Full->new();
$stat->add_data(@decade);
my $decade_stddev = $stat->standard_deviation();

foreach my $year (2020..2022) {
    my $z = ($data{$year} - mean(@decade)) / $decade_stddev;
    print "Z-score for $year: $z\n";
}

sub mean {
    my @data = @_;
    my $total = 0;
    $total += $_ for @data;
    return $total / @data;
}